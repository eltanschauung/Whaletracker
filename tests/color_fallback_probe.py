#!/usr/bin/env python3
"""Offline differential C++ proxy of the extracted SourcePawn color function.

Executes translated function bodies against DB/native stubs, not SourceMod.
Also executes the extracted joined SELECT against in-memory SQLite fixtures.
No network or production data. Requires g++ or clang++.
"""
from pathlib import Path
import re
import shutil
import sqlite3
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PATH = "scripting/whaletracker/commands_whaletracker.sp"

def function(text):
    start = text.index("void GetNameColorTagForSteamId(")
    end = text.index("\nvoid UpdateWhalePointsCacheMetadata", start)
    return text[start:end]

def joined_query(text):
    body = function(text)
    match = re.search(r'Format\(query, sizeof\(query\),\s*(.*?)\s*,\s*escapedSteamId\);', body, re.S)
    assert match
    return "".join(re.findall(r'"([^"\n]*)"', match[1]))

def translate(body, name):
    body = body.replace("GetNameColorTagForSteamId", name)
    body = body.replace("const char[] steamId, char[] colorTag", "const char* steamId, char* colorTag")
    body = body.replace("\n        ... ", "\n        ")
    body = body.replace("results.", "results->")
    body = re.sub(r"\bnull\b", "nullptr", body)
    return body

STUBS = r'''
#include <algorithm>
#include <cassert>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <iostream>
#include <optional>
#include <string>
#include <vector>
constexpr int STEAMID64_LEN=21;
bool g_bDatabaseReady=true;
void* g_hDatabase=(void*)1;
void strcopy(char* out, int size, const char* text) { if(size>0) std::snprintf(out,size,"%s",text); }
void TrimString(char* text) {
    std::string s=text;
    auto white=[](unsigned char c){return c<=32;};
    auto begin=std::find_if_not(s.begin(),s.end(),white);
    auto end=std::find_if_not(s.rbegin(),s.rend(),white).base();
    s=begin<end ? std::string(begin,end) : "";
    std::strcpy(text,s.c_str());
}
void EscapeSqlString(const char* in,char* out,int size){strcopy(out,size,in);}
void Format(char* out,int size,const char* fmt,...) {va_list args;va_start(args,fmt);vsnprintf(out,size,fmt,args);va_end(args);}
struct Row {bool exists;std::optional<std::string> color;};
Row filter,cache;
bool filter_error,cache_error,join_error;
int queries,native_mode;
std::string native_value;
bool TryGetFiltersSteamIdColorTag(const char*,char* out,int size) {
    out[0]=0;
    if(native_mode<0)return false;
    strcopy(out,size,native_value.c_str());
    if(native_mode==0)return false;
    TrimString(out);return out[0]!=0;
}
struct Result {
    std::vector<std::optional<std::string>> fields;
    bool row,read=false;
    bool FetchRow(){bool yes=row&&!read;read=true;return yes;}
    bool IsFieldNull(int col){return !fields.at(col).has_value();}
    void FetchString(int col,char* out,int size){strcopy(out,size,fields.at(col).value_or("").c_str());}
};
using DBResultSet=Result*;
bool SQL_HasResultSet(DBResultSet r){return r!=nullptr;}
DBResultSet SQLQuerySync(const char* query) {
    ++queries;
    if(std::strstr(query,"LEFT JOIN")) {
        if(filter_error||cache_error||join_error)return nullptr;
        return new Result{{filter.exists?std::optional<std::string>("1"):std::nullopt,filter.color,
                           cache.exists?std::optional<std::string>("1"):std::nullopt,cache.color},true};
    }
    bool isfilter=std::strstr(query,"SELECT color FROM")!=nullptr;
    Row r=isfilter?filter:cache;
    if(isfilter?filter_error:cache_error)return nullptr;
    return new Result{{r.color},r.exists};
}
'''

MAIN = r'''
int main(){
    std::vector<Row> rows={{false,std::nullopt},{true,std::nullopt},{true,""},{true,"   "},{true,"\t\n"},{true," red "},{true,"é界"}};
    int cases=0;
    for(auto f:rows) for(auto c:rows) for(int errors=0;errors<8;++errors)
    for(int mode=-1;mode<=1;++mode) for(auto native:{""," purple "}) for(int size:{1,2,4,32}) {
        filter=f;cache=c;filter_error=errors&1;cache_error=errors&2;join_error=errors&4;
        native_mode=mode;native_value=native;
        for(int ready=0;ready<2;++ready) for(auto steam:{"","76561198000000000"}) {
            g_bDatabaseReady=ready;
            char old[32]={},now[32]={};queries=0;
            Before(steam,old,size);int old_queries=queries;queries=0;
            After(steam,now,size);int new_queries=queries;
            if(std::strcmp(old,now)){std::cerr<<"mismatch case "<<cases<<"\n";return 1;}
            if(!ready||!steam[0]||old_queries==0)assert(new_queries==0);
            else if(!filter_error&&!cache_error&&!join_error)assert(new_queries==1);
            else assert(new_queries==old_queries+1);
            ++cases;
        }
    }
    std::cout<<"color C++ proxy differential cases="<<cases<<" passed\n";
    std::cout<<"color query-count proxy: empty/whitespace/missing filter fallback 2 -> 1; native success 0 -> 0; nonempty filter 1 -> 1; error path adds 1 failed joined query\n";
}
'''

def main():
    current = (ROOT / PATH).read_text()
    disconnect = current.split("void CacheWhalePointsOnDisconnect(", 1)[1].split("\nbool IsValidClient", 1)[0]
    assert "GetNameColorTagForSteamId(" not in disconnect
    assert disconnect.count("UpdateWhalePointsCacheMetadata(") == 1
    assert 'UpdateWhalePointsCacheMetadata(g_Stats[client].steamId, "", GetClientUserId(client))' in disconnect
    metadata = current.split("void UpdateWhalePointsCacheMetadata(", 1)[1].split("\nvoid CacheWhalePointsOnDisconnect", 1)[0]
    assert metadata.count("GetNameColorTagForSteamId(") == 1
    assert "!g_bDatabaseReady" in metadata and "EnsureClientSteamId(client)" in disconnect
    print("disconnect source contract: exactly one color resolution, readiness/SteamID/user ID preserved")
    baseline = subprocess.check_output(["git", "show", f"4c68b84:{PATH}"], cwd=ROOT, text=True)
    compiler = shutil.which("g++") or shutil.which("clang++")
    assert compiler, "C++ compiler required"
    with tempfile.TemporaryDirectory(prefix="wt-color-proxy-") as directory:
        source = Path(directory) / "probe.cpp"
        executable = Path(directory) / "probe"
        source.write_text(STUBS + translate(function(baseline), "Before") + translate(function(current), "After") + MAIN)
        subprocess.run([compiler, "-std=c++17", "-O1", "-fsanitize=address,undefined", str(source), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)
    db = sqlite3.connect(":memory:")
    db.executescript("CREATE TABLE filters_namecolors(steamid TEXT PRIMARY KEY,color TEXT); CREATE TABLE whaletracker_points_cache(steamid TEXT PRIMARY KEY,name_color TEXT);")
    query = joined_query(current).replace("'%s'", "?")
    count = 0
    for filter_row in [[], [("1", None)], [("1", "")], [("1", "  ")], [("1", " blue ")]]:
        for cache_row in [[], [("1", None)], [("1", "")], [("1", " green ")]]:
            db.execute("DELETE FROM filters_namecolors")
            db.execute("DELETE FROM whaletracker_points_cache")
            db.executemany("INSERT INTO filters_namecolors VALUES (?,?)", filter_row)
            db.executemany("INSERT INTO whaletracker_points_cache VALUES (?,?)", cache_row)
            result = db.execute(query, ("1",)).fetchall()
            assert result == [(filter_row[0][0] if filter_row else None, filter_row[0][1] if filter_row else None,
                               cache_row[0][0] if cache_row else None, cache_row[0][1] if cache_row else None)], result
            count += 1
    print(f"extracted joined SQL: SQLite fixture combinations={count} passed")

if __name__ == "__main__":
    main()
