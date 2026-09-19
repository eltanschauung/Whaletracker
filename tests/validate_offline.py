#!/usr/bin/env python3
"""Offline source contracts, protocol-state models and extracted SQLite SQL tests.

These checks DO NOT compile or execute Rust or SourcePawn. Model tests are
independent specifications, not a replacement for the shipped native Rust tests.
The cache SQL tests execute the SELECT/INSERT text extracted from points_cache.rs
in SQLite with registered math functions/collation; they do not test MariaDB DDL.
"""
from __future__ import annotations
import argparse
from collections import deque
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import random
import re
import sqlite3
import threading
import tomllib
import unittest

ROOT: Path
REPO: str

class BudgetModel:
    """Reference model: leased/executing jobs keep capacity until retirement."""
    def __init__(self, rows: int, size: int):
        self.row_limit, self.byte_limit = rows, size
        self.lock = threading.Lock()
        self.jobs: dict[str, tuple[int, int]] = {}
    def reserve(self, specs):
        with self.lock:
            ids = [key for key, _, _ in specs]
            if len(set(ids)) != len(ids) or any(key in self.jobs for key in ids):
                return False
            if len(self.jobs) + len(specs) > self.row_limit:
                return False
            if sum(size for size, _ in self.jobs.values()) + sum(size for _, size, _ in specs) > self.byte_limit:
                return False
            self.jobs.update({key:(size,lane) for key,size,lane in specs})
            return True
    def retire(self, ids):
        with self.lock:
            for key in ids:
                del self.jobs[key]

class TransportModel:
    """Reference for one batch and a local-write handoff barrier."""
    def __init__(self):
        self.queue = deque()
        self.flight = []
        self.batch = 0
        self.local = deque()
    def send(self, batch, count):
        assert not self.flight
        self.flight = [self.queue.popleft() for _ in range(min(count,len(self.queue)))]
        self.batch = batch
    def disconnect(self):
        self.queue.extendleft(reversed(self.flight))
        self.flight = []
        self.batch = 0
    def ack(self, batch, accepted, executed, errors):
        if batch != self.batch or not self.flight:
            return False
        if accepted != executed or accepted > len(self.flight) or errors:
            return False
        self.flight = []
        self.batch = 0
        return True
    def can_pump_local(self):
        return not self.queue and not self.flight

class ModelTests(unittest.TestCase):
    def test_reserved_rows_include_executing_work(self):
        b=BudgetModel(2,100); self.assertTrue(b.reserve([('a',60,0)]))
        self.assertFalse(b.reserve([('b',41,2)])); self.assertEqual(len(b.jobs),1)
    def test_whole_batch_reservation_rolls_back(self):
        b=BudgetModel(2,100)
        self.assertFalse(b.reserve([('a',10,0),('b',10,1),('c',10,2)])); self.assertFalse(b.jobs)
    def test_active_duplicate_is_not_reexecuted(self):
        b=BudgetModel(2,100); b.reserve([('a',1,0)])
        self.assertFalse(b.reserve([('a',1,2)])); b.retire(['a'])
        self.assertTrue(b.reserve([('a',1,2)]))
    def test_duplicate_ids_in_one_batch_are_atomic(self):
        b=BudgetModel(10,100)
        self.assertFalse(b.reserve([('a',1,0),('a',1,1)])); self.assertFalse(b.jobs)
    def test_concurrent_three_lane_reservations(self):
        b=BudgetModel(12,1200); start=threading.Barrier(33); ready=threading.Barrier(33); release=threading.Barrier(33)
        failures=[]
        def worker(n):
            try:
                start.wait(10)
                ids=[f'{n}-{lane}' for lane in range(3)]
                granted=b.reserve([(key,100,lane) for lane,key in enumerate(ids)])
                ready.wait(10); release.wait(10)
                if granted: b.retire(ids)
            except BaseException as e: failures.append(str(e))
        workers=[threading.Thread(target=worker,args=(n,)) for n in range(32)]
        for w in workers: w.start()
        start.wait(10); ready.wait(10)
        observed=(len(b.jobs),sum(size for size,_ in b.jobs.values()))
        release.wait(10)
        for w in workers: w.join(10)
        self.assertFalse(failures); self.assertEqual(observed,(12,1200)); self.assertFalse(b.jobs)
    def test_fifo_retry_precedes_newer_work(self):
        m=TransportModel(); m.queue.extend(['a','b','c']); m.send(1,2)
        m.queue.append('d'); m.disconnect(); self.assertEqual(list(m.queue),['a','b','c','d'])
    def test_late_ack_cannot_release_new_batch(self):
        m=TransportModel(); m.queue.extend(['a','b']); m.send(2,2)
        self.assertFalse(m.ack(1,2,2,0)); self.assertEqual(m.flight,['a','b'])
    def test_ack_error_retains_ownership(self):
        m=TransportModel(); m.queue.append('a'); m.send(1,1)
        self.assertFalse(m.ack(1,1,1,1)); self.assertFalse(m.can_pump_local())
    def test_deduplicated_success_ack_is_allowed(self):
        m=TransportModel(); m.queue.append('a'); m.send(1,1)
        self.assertTrue(m.ack(1,0,0,0)); self.assertTrue(m.can_pump_local())
    def test_local_write_cannot_pass_uncertain_remote(self):
        m=TransportModel(); m.queue.append('old'); m.send(1,1); m.local.append('new')
        m.disconnect(); self.assertFalse(m.can_pump_local())
        m.send(2,1); m.ack(2,1,1,0); self.assertTrue(m.can_pump_local())
    def test_timeout_is_not_cancellation(self):
        b=BudgetModel(1,100); b.reserve([('a',1,0)])
        # A handler stops waiting; it does not own or destroy the job permit.
        self.assertIn('a',b.jobs); b.retire(['a']); self.assertFalse(b.jobs)
    def test_done_marker_failure_never_reexecutes_committed_sql(self):
        executions=0; marker_attempts=0; ack=False
        executions += 1
        for marker_failed in [True,True,False]:
            marker_attempts += 1
            if not marker_failed: ack=True; break
        self.assertEqual((executions,marker_attempts,ack),(1,3,True))
    def test_replay_order_is_physical_not_lexical(self):
        pending={key:(n,123) for n,key in enumerate(['id-2','id-10','id-1'])}
        self.assertEqual(sorted(pending,key=lambda key:pending[key][0]),['id-2','id-10','id-1'])

class SourceContractTests(unittest.TestCase):
    def source(self,name): return (ROOT/name).read_text(encoding='utf-8')
    def test_manifest_declares_actual_minimum_rust(self):
        cargo=tomllib.loads(self.source('Cargo.toml'))
        self.assertEqual(cargo['package']['rust-version'],'1.89')
        self.assertEqual(cargo['dependencies']['mysql'],'26')
        self.assertEqual(cargo['profile']['release']['panic'],'abort')
    def test_journal_locks_have_stable_sidecar(self):
        text=self.source('src/journal_lock.rs')
        self.assertIn('file.try_lock()',text); self.assertIn('lock_name.push(".lock")',text)
        self.assertNotIn('remove_file',text)
    def test_connections_have_raii_bound_and_absolute_deadline(self):
        text=self.source('src/runtime_limits.rs')
        self.assertIn('fetch_update',text); self.assertIn('impl Drop for ConnectionPermit',text)
        self.assertIn('saturating_duration_since(Instant::now())',text)
    def test_missing_response_fields_cannot_confirm_work(self):
        name='sourcemod/scripting/plugin_statistics/transport.sp' if REPO=='statistics' else 'scripting/whaletracker/rust_sql_outlet_whaletracker.sp'
        text=self.source(name)
        for field in ('HasBatchId','HasAccepted','HasExecuted','HasDbErrors'):
            self.assertIn(field,text)
    def test_source_files_are_utf8_and_not_truncated(self):
        sources=list(ROOT.rglob('*.rs'))+list(ROOT.rglob('*.sp'))
        self.assertGreater(len(sources),5)
        for p in sources:
            text=p.read_text(encoding='utf-8')
            self.assertNotIn('\x00',text,str(p)); self.assertNotIn('... (truncated)',text,str(p))
    def test_rust_module_paths_resolve(self):
        main=self.source('src/main.rs')
        for name in re.findall(r'^mod ([a-z_]+);',main,re.M):
            self.assertTrue((ROOT/f'src/{name}.rs').is_file(),name)
    def test_whale_barrier_patch_is_mandatory(self):
        if REPO!='whaletracker': self.skipTest('WhaleTracker-only helper contract')
        text=self.source('scripting/whaletracker/rust_sql_outlet_whaletracker.sp')
        self.assertIn('#if !defined WT_CONCURRENCY_HELPERS',text)
        self.assertIn('WhaleTracker_RustCanPumpLocal()',text)
        self.assertIn('WhaleTracker_RustHasLocalWork()',text)
    def test_marker_retry_is_separate_from_sql_execution(self):
        if REPO=='statistics':
            text=self.source('src/main.rs')
            region=text.split('fn finish_written_events(',1)[1].split('#[derive(Default)]',1)[0]
            self.assertIn('while let Err(err) = pending_journal.append_done_batch',region)
        else:
            text=self.source('src/sink.rs')
            region=text.split('fn confirm_committed(',1)[1]
            self.assertIn('while let Err(err) = self.journal.append_done',region)
        self.assertNotIn('query_drop(',region); self.assertNotIn('write_records(',region)

class HelperInstallerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if REPO!='whaletracker': raise unittest.SkipTest('WhaleTracker-only installer')
        spec=importlib.util.spec_from_file_location('guard_installer',ROOT/'tools/apply_helpers.py')
        cls.module=importlib.util.module_from_spec(spec); spec.loader.exec_module(cls.module)
        cls.fixture='\n'.join(old+'\n}\n' for old,_ in cls.module.PATCHES).encode()
    def test_all_six_guard_sites(self):
        result=self.module.transform(self.fixture,check_hash=False).decode()
        self.assertEqual(len(self.module.PATCHES),6)
        for _,new in self.module.PATCHES: self.assertIn(new,result)
    def test_guard_transform_is_idempotent(self):
        first=self.module.transform(self.fixture,check_hash=False)
        self.assertEqual(self.module.transform(first),first)
    def test_unverified_local_file_is_refused(self):
        with self.assertRaises(ValueError): self.module.transform(self.fixture)
    def test_marker_with_missing_guard_is_refused(self):
        with self.assertRaises(ValueError): self.module.transform((self.module.MARKER+'\n').encode())
    def test_duplicate_patch_site_is_refused(self):
        with self.assertRaises(ValueError): self.module.transform(self.fixture+self.fixture,check_hash=False)
    def test_missing_patch_site_is_refused(self):
        with self.assertRaises(ValueError): self.module.transform(b'// missing',check_hash=False)

class ExtractedCacheSqlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if REPO!='whaletracker': raise unittest.SkipTest('WhaleTracker-only cache SQL')
        cls.source=(ROOT/'src/points_cache.rs').read_text()
        cls.expr=re.search(r'const WHALE_POINTS_SQL_EXPR: &str = r#"(.*?)"#;',cls.source,re.S).group(1)
        maps_block=re.search(r'const RANKED_MAPS: &\[&str\] = &\[(.*?)\];',cls.source,re.S).group(1)
        cls.maps=', '.join(f"'{value}'" for value in re.findall(r'"([^"]+)"',maps_block))
        query=re.search(
            r'format!\(\s*"(INSERT INTO whaletracker_points_cache_build.*?)",\s*min_duration =',
            cls.source,
            re.S,
        ).group(1)
        cls.template=re.sub(r'\\\n\s*','',query)
    def setUp(self):
        self.db=sqlite3.connect(':memory:'); self.addCleanup(self.db.close)
        self.db.create_function('SQRT',1,math.sqrt); self.db.create_function('LN',1,math.log)
        self.db.create_function('GREATEST',-1,lambda *values:max(values))
        self.db.create_function('SUBSTRING_INDEX',3,self.substring_index)
        self.db.create_collation('utf8mb4_uca1400_ai_ci',lambda a,b:(a.casefold()>b.casefold())-(a.casefold()<b.casefold()))
        self.db.executescript('''CREATE TABLE whaletracker (steamid TEXT PRIMARY KEY,cached_personaname TEXT);
CREATE TABLE filters_namecolors (steamid TEXT PRIMARY KEY,color TEXT);
CREATE TABLE whaletracker_logs (log_id TEXT PRIMARY KEY,map TEXT,started_at INTEGER,ended_at INTEGER,duration INTEGER,finalized INTEGER);
CREATE TABLE whaletracker_log_players (log_id TEXT,steamid TEXT,kills INTEGER,deaths INTEGER,assists INTEGER,damage INTEGER,healing INTEGER,total_ubers INTEGER);
CREATE TABLE whaletracker_points_cache (steamid TEXT PRIMARY KEY,points INTEGER,rank INTEGER,name_color TEXT,updated_at INTEGER,matches_used INTEGER,rolling_kills INTEGER,rolling_deaths INTEGER,window_started_at INTEGER,window_ended_at INTEGER);
CREATE TABLE whaletracker_points_cache_build (steamid TEXT PRIMARY KEY,points INTEGER,rank INTEGER,name_color TEXT,updated_at INTEGER,matches_used INTEGER,rolling_kills INTEGER,rolling_deaths INTEGER,window_started_at INTEGER,window_ended_at INTEGER);''')
    @staticmethod
    def substring_index(value,delimiter,count):
        parts=value.split(delimiter)
        if count > 0: return delimiter.join(parts[:count])
        if count < 0: return delimiter.join(parts[count:])
        return ''
    def insert(self,id,k,d,a=0,dmg=1000,h=0,u=0,matches=50,duration=301,map_name='cp_sunshine'):
        self.db.execute('INSERT INTO whaletracker VALUES (?,?)',(id,id))
        for n in range(matches):
            log_id=f'{id}-{n}'
            self.db.execute('INSERT INTO whaletracker_logs VALUES (?,?,?,?,?,1)',
                (log_id,map_name,1000+n,2000+n,duration))
            self.db.execute('INSERT INTO whaletracker_log_players VALUES (?,?,?,?,?,?,?,?)',
                (log_id,id,k,d,a,dmg,h,u))
    def rebuild(self):
        self.db.execute(self.template.format(
            now=1234567890,expr=self.expr,min_duration=300,min_kills_assists=5,
            max_matches=300,min_matches=50,maps=self.maps))
        return self.db.execute('SELECT steamid,points,rank,name_color,updated_at,matches_used,rolling_kills,rolling_deaths FROM whaletracker_points_cache_build ORDER BY steamid').fetchall()
    def test_thresholds_and_stable_tie_break(self):
        self.insert('1',10,10); self.insert('2',10,10)
        self.insert('3',10,10,matches=49); self.insert('4',10,10,duration=300)
        rows=self.rebuild()
        self.assertEqual([r[2] for r in rows],[1,2,0,0])
        self.assertEqual(rows[0][1],rows[1][1])
    def test_name_color_precedence_and_fallback(self):
        for id in ['1','2','3']: self.insert(id,10,10)
        self.db.execute("INSERT INTO filters_namecolors VALUES ('1','cyan')")
        self.db.executemany('INSERT INTO whaletracker_points_cache VALUES (?,0,0,?,0,0,0,0,0,0)',[('1','red'),('2','blue')])
        self.assertEqual([r[3] for r in self.rebuild()],['cyan','blue','gold'])
    def test_formula_against_independent_math_for_32_players(self):
        rng=random.Random(789); expected={}
        for n in range(32):
            k,d,a,dmg,h,u=[rng.randrange(0,v) for v in [100,100,100,20000,20000,20]]
            if k+a <= 5: k=6
            self.insert(str(n),k,d,a,dmg,h,u)
            k*=50; d*=50; a*=50; dmg*=50; h*=50; u*=50
            eng=max(k+d,1)
            value=1000*math.sqrt(eng/(eng+400))*(5*(k+0.35*a)/(d+20)+math.log1p(dmg/(150*eng))+0.60*math.log1p(h/(100*eng))+0.90*math.log1p(60*u/eng))
            expected[str(n)]=math.floor(value+0.5)
        rows=self.rebuild(); self.assertEqual(len(rows),32)
        for id,points,rank,color,at,matches,kills,deaths in rows:
            self.assertEqual(points,expected[id],id); self.assertEqual(at,1234567890)
    def test_cache_includes_rolling_kd_totals(self):
        self.insert('1',7,3,a=2)
        row=self.rebuild()[0]
        self.assertEqual(row[6:8],(350,150))
    def test_nonpositive_stats_do_not_produce_domain_error(self):
        self.insert('1',-1,-2,-3,-10,-20,-30)
        row=self.rebuild()[0]; self.assertEqual(row[1:3],(0,0))
    def test_map_normalization_accepts_workshop_ugc_suffix(self):
        self.insert('1',10,10,map_name='workshop/cp_sunshine.ugc454207393')
        row=self.rebuild()[0]
        self.assertEqual(row[2],1)
    def test_generation_cas_keeps_same_millisecond_new_work(self):
        self.db.execute('CREATE TABLE whaletracker_points_cache_state (cache_key TEXT,dirty INTEGER,dirty_since INTEGER,last_rebuilt_at INTEGER,last_reason TEXT,dirty_generation INTEGER)')
        self.db.execute("INSERT INTO whaletracker_points_cache_state VALUES ('global',1,1000,0,'pending',5)")
        clear=re.search(r'"(UPDATE whaletracker_points_cache_state SET dirty = 0,.*?)",\s*params!',self.source,re.S).group(1)
        clear=re.sub(r'\\\n\s*','',clear)
        clear=clear.replace('CAST(UNIX_TIMESTAMP(CURRENT_TIMESTAMP(3))*1000 AS UNSIGNED)','1000')
        self.db.execute('UPDATE whaletracker_points_cache_state SET dirty_generation=6')
        self.db.execute(clear,{'generation':5})
        self.assertEqual(self.db.execute('SELECT dirty FROM whaletracker_points_cache_state').fetchone()[0],1)
        self.db.execute(clear,{'generation':6})
        self.assertEqual(self.db.execute('SELECT dirty FROM whaletracker_points_cache_state').fetchone()[0],0)

def main():
    global ROOT,REPO
    p=argparse.ArgumentParser(description=__doc__); p.add_argument('root',nargs='?',type=Path,default=Path(__file__).resolve().parents[1]); p.add_argument('--json',type=Path)
    args=p.parse_args(); ROOT=args.root.resolve()
    name=tomllib.loads((ROOT/'Cargo.toml').read_text())['package']['name']
    REPO='statistics' if name=='sourcemod-plugin-statistics' else 'whaletracker'
    classes=[ModelTests,SourceContractTests]
    if REPO=='whaletracker': classes += [HelperInstallerTests,ExtractedCacheSqlTests]
    suite=unittest.TestSuite()
    for cls in classes:
        for test in unittest.defaultTestLoader.loadTestsFromTestCase(cls):
            if REPO=='statistics' and test._testMethodName=='test_whale_barrier_patch_is_mandatory': continue
            suite.addTest(test)
    result=unittest.TextTestRunner(verbosity=2).run(suite)
    summary={'repository':name,'status':'passed' if result.wasSuccessful() else 'failed','tests_run':result.testsRun,'skipped':len(result.skipped),'failures':len(result.failures),'errors':len(result.errors),'scope':('Python reference models and source contracts' + ('; installer fixtures and extracted cache SQL in SQLite' if REPO=='whaletracker' else '') + '; no Rust/SourcePawn compilation or MariaDB integration')}
    if args.json: args.json.write_text(json.dumps(summary,indent=2)+'\n')
    print(json.dumps(summary,indent=2))
    return 0 if result.wasSuccessful() else 1
if __name__=='__main__': raise SystemExit(main())
