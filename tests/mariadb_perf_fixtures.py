#!/usr/bin/env python3
"""Opt-in MariaDB fixture checks via the existing safe Kogasa DB helper.

Mutates ONLY connection-local TEMPORARY fixture tables. Reads production schema
with LIKE; never reads production rows. SELECT table names are substituted.
Does not execute the daemon poll function or rebuild/ranking SQL.
python3 tests/mariadb_perf_fixtures.py --helper /home/kogasa/Kogasatopia/tools/kogasa_db.py
"""
import argparse
import importlib.util
from pathlib import Path
import subprocess
import os
import re
import sys
import uuid

sys.dont_write_bytecode = True
from color_fallback_probe import ROOT, joined_query

def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--helper", type=Path, required=True)
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location("safe_db", args.helper)
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    config = helper.parse_databases_cfg(helper.DEFAULT_DB_CONFIG, "default")
    mysql = helper.mysql_args("mysql", config)
    password = config.get("pass", "")
    query = joined_query((ROOT / "scripting/whaletracker/commands_whaletracker.sp").read_text())
    query = query.replace("%s", "76561198000000000")
    statements = [
        "CREATE TEMPORARY TABLE wt_perf_filters LIKE filters_namecolors;",
        "CREATE TEMPORARY TABLE wt_perf_cache LIKE whaletracker_points_cache;",
        "CREATE TEMPORARY TABLE wt_perf_state LIKE whaletracker_points_cache_state;",
    ]
    expected = []
    # Non-NULL colors use actual table definitions/defaults; nullable source
    # fields, missing rows, and row presence are covered by the offline proxy.
    for f in [None, "", "   ", " red "]:
        for c in [None, "", "  ", " blue "]:
            statements.extend(["DELETE FROM filters_namecolors;", "DELETE FROM whaletracker_points_cache;"])
            if f is not None:
                statements.append(f"INSERT INTO filters_namecolors (steamid,color) VALUES ('76561198000000000','{f}');")
            if c is not None:
                statements.append(f"INSERT INTO whaletracker_points_cache (steamid,name_color) VALUES ('76561198000000000','{c}');")
            # HEX keeps whitespace observable despite CLI line splitting.
            statements.append("SELECT " + ",".join(f"IFNULL(HEX(t.{column}),'NULL')" for column in ["steamid", "color", "cache_id", "name_color"]) +
                " FROM (" + query.replace("f.steamid, f.color, c.steamid, c.name_color", "f.steamid, f.color, c.steamid AS cache_id, c.name_color") + ") t;")
            sid = "76561198000000000".encode().hex().upper()
            expected.append("\t".join([sid if f is not None else "NULL", f.encode().hex().upper() if f is not None else "NULL",
                                       sid if c is not None else "NULL", c.encode().hex().upper() if c is not None else "NULL"]))
    statements.extend([
        "INSERT INTO whaletracker_points_cache_state (cache_key,dirty,dirty_updated_at,dirty_generation,dirty_since) VALUES ('global',1,1000,7,1000);",
        # Simulate invalidation during rebuild with an unchanged generation ACK.
        "UPDATE whaletracker_points_cache_state SET dirty_generation=8 WHERE cache_key='global';",
        "UPDATE whaletracker_points_cache_state SET dirty=0,dirty_since=0 WHERE cache_key='global' AND dirty=1 AND dirty_generation=7;",
        "SELECT dirty,dirty_generation,dirty_since FROM whaletracker_points_cache_state WHERE cache_key='global';",
    ])
    expected.append("1\t8\t1000")
    fixtures = "\n".join(statements[3:]).replace("whaletracker_points_cache_state", "wt_perf_state").replace("whaletracker_points_cache", "wt_perf_cache").replace("filters_namecolors", "wt_perf_filters")
    actual = helper.mysql_query(mysql, password, "\n".join(statements[:3]) + "\n" + fixtures).splitlines()
    assert actual == expected, "isolated MariaDB fixture mismatch"
    print("MariaDB: 16 extracted color SELECT fixtures + generation-guard invalidation fixture passed")

    # Two real sessions, unique lock name; no daemon lock/table is used. Hold the
    # first lock while session two attempts it, then verify release/reacquisition.
    lock = "wt-perf-fixture-" + uuid.uuid4().hex
    env = os.environ.copy()
    if password:
        env["MYSQL_PWD"] = password
    owner = subprocess.Popen(mysql + ["--unbuffered"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL, text=True, env=env)
    try:
        owner.stdin.write(f"SELECT GET_LOCK('{lock}',0);\n")
        owner.stdin.flush()
        assert owner.stdout.readline().strip() == "1"
        assert helper.mysql_query(mysql, password, f"SELECT GET_LOCK('{lock}',0);").strip() == "0"
        owner.stdin.write(f"SELECT RELEASE_LOCK('{lock}');\n")
        owner.stdin.flush()
        assert owner.stdout.readline().strip() == "1"
        assert helper.mysql_query(mysql, password, f"SELECT GET_LOCK('{lock}',0); SELECT RELEASE_LOCK('{lock}');").splitlines() == ["1", "1"]
    finally:
        owner.stdin.close()
        owner.wait(timeout=5)
    print("MariaDB: isolated two-session named-lock exclusion/release passed")

if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.SubprocessError) as error:
        # DB helper errors may contain connection details; never emit them.
        code = re.search(r"ERROR (\d+).*?at line (\d+)", str(error))
        detail = f" code={code[1]} fixture_line={code[2]}" if code else ""
        raise SystemExit("MariaDB fixture execution failed" + detail + " (connection details suppressed)") from None
