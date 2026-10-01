"""Offline wiring/SQL contracts; these do not execute the SourcePawn VM."""
from pathlib import Path
import re
import sqlite3
import unittest

ROOT = Path(__file__).resolve().parents[1]
MODULE = (ROOT / 'scripting/whaletracker/whale_demos.sp').read_text()


class WhaleDemosTest(unittest.TestCase):
    def test_replaces_old_round_capture_with_admin_check_pipeline(self):
        runtime = (ROOT / 'scripting/whaletracker/runtime_whaletracker.sp').read_text()
        self.assertFalse((ROOT / 'scripting/whaletracker/demo_recording.sp').exists())
        self.assertNotIn('WhaleTracker_CaptureRoundDemo', runtime)
        admin_check = runtime.split('public void OnClientPostAdminCheck(int client)', 1)[1].split('public ', 1)[0]
        self.assertIn('WhaleDemos_OnClientPostAdminCheck(client)', admin_check)
        map_start = runtime.split('public void OnMapStart()', 1)[1].split('public void OnMapEnd()', 1)[0]
        self.assertIn('WhaleDemos_OnClientPostAdminCheck(i)', map_start)
        self.assertLess(map_start.index('BeginMatchTracking()'), map_start.index('WhaleDemos_OnClientPostAdminCheck(i)'))
        self.assertIn('DGM_RealPlayerCount() > 7', MODULE)
        self.assertIn('IsFakeClient(client)', MODULE)

    def test_async_guard_and_success_only_stamp(self):
        self.assertIn('g_WhaleDemosQueryPending = true', MODULE)
        self.assertIn('generation != g_WhaleDemosGeneration', MODULE)
        self.assertIn('!StrEqual(logId, g_sCurrentLogId)', MODULE)
        self.assertIn('result.FetchRow() && !result.IsFieldNull(0)', MODULE)
        self.assertLess(MODULE.index('SourceTV_StartRecording(filename)'), MODULE.index('strcopy(g_WhaleDemoFile'))
        self.assertIn('!SourceTV_IsRecording()', MODULE)
        reconnect = MODULE.split('void WhaleDemos_EnsureColumn()', 1)[1].split('public void', 1)[0]
        self.assertIn('g_WhaleDemosGeneration++', reconnect)
        self.assertIn('g_WhaleDemosQueryPending = false', reconnect)

    def test_filename_is_native_safe_and_does_not_overwrite(self):
        self.assertIn('"sept"', MODULE)
        self.assertIn('"%H-%M"', MODULE)
        self.assertNotIn('"%H:%M"', MODULE)
        self.assertIn('FileExists(filename, true)', MODULE)
        self.assertIn('WhaleDemos_FilenameExists(filename)', MODULE)
        self.assertIn('"/var/www/fastdl/demos/%s"', MODULE)
        self.assertIn('return FileExists(published)', MODULE)
        self.assertIn('"%s_%d.dem"', MODULE)

    def test_schema_callback_uses_connection_not_handle_or_match_identity(self):
        ensure = MODULE.split('void WhaleDemos_EnsureColumn()', 1)[1].split('public void', 1)[0]
        callback = MODULE.split('public void WhaleDemos_ColumnReady(', 1)[1].split('bool WhaleDemos_HasSourceTV()', 1)[0]
        self.assertIn('g_iDatabaseConnectGeneration);', ensure)
        self.assertIn('data != g_iDatabaseConnectGeneration', callback)
        self.assertIn('g_bShuttingDown', callback)
        self.assertNotIn('db != g_hDatabase', MODULE)
        # Map resets must not discard a successful schema query for the current connection.
        self.assertNotIn('g_WhaleDemosGeneration', callback)
        self.assertLess(callback.index('data != g_iDatabaseConnectGeneration'),
                        callback.index('g_WhaleDemosColumnReady = true'))

    def test_lookup_captures_connection_and_match_generations_in_order(self):
        request = MODULE.split('void WhaleDemos_TryStart()', 1)[1].split('public void WhaleDemos_CheckCurrentRow', 1)[0]
        callback = MODULE.split('public void WhaleDemos_CheckCurrentRow(', 1)[1].split('void WhaleDemos_BuildFilename', 1)[0]
        self.assertLess(request.index('pack.WriteCell(g_iDatabaseConnectGeneration)'),
                        request.index('pack.WriteCell(g_WhaleDemosGeneration)'))
        self.assertLess(callback.index('int connectionGeneration = pack.ReadCell()'),
                        callback.index('int generation = pack.ReadCell()'))
        self.assertLess(callback.index('delete pack'), callback.index('connectionGeneration !='))
        # Stale callbacks must not release a query lease belonging to the new connection/match.
        for guard in ('g_bShuttingDown', 'connectionGeneration != g_iDatabaseConnectGeneration',
                      'generation != g_WhaleDemosGeneration', '!StrEqual(logId, g_sCurrentLogId)'):
            self.assertLess(callback.index(guard), callback.index('g_WhaleDemosQueryPending = false'))
        self.assertLess(callback.index('g_WhaleDemosQueryPending = false'),
                        callback.index('if (error[0] || result == null)'))

    def test_null_row_check_and_filename_preservation_use_shipped_sql(self):
        select = re.search(r'"(SELECT demo_filename FROM whaletracker_logs[^"\n]+)"', MODULE).group(1)
        update = re.search(r'", demo_filename = (COALESCE\([^"\n]+)"', MODULE).group(1)
        db = sqlite3.connect(':memory:')
        self.addCleanup(db.close)
        db.execute('CREATE TABLE whaletracker_logs (log_id TEXT PRIMARY KEY, demo_filename TEXT)')
        self.assertIsNone(db.execute(select % 'new').fetchone())
        db.execute("INSERT INTO whaletracker_logs VALUES ('new', NULL)")
        self.assertEqual(db.execute(select % 'new').fetchone(), (None,))
        sqlite_update = update.replace('VALUES(demo_filename)', 'excluded.demo_filename')
        query = ('INSERT INTO whaletracker_logs VALUES (?, ?) '
                 'ON CONFLICT(log_id) DO UPDATE SET demo_filename = ' + sqlite_update)
        filename = 'koth_genbu_ravine_b1_sept_30_14-36.dem'
        db.execute(query, ('new', filename))
        self.assertEqual(db.execute(select % 'new').fetchone(), (filename,))
        db.execute(query, ('new', None))
        db.execute(query, ('new', 'unexpected.dem'))
        self.assertEqual(db.execute(select % 'new').fetchone(), (filename,))


if __name__ == '__main__':
    unittest.main()
