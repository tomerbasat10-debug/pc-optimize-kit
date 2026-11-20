# Measure-Dpc.ps1 - READ-ONLY DPC/ISR latency measurement (LatencyMon equivalent, fully scriptable). Run ELEVATED.
# Records DPC+ISR+image-load events with the built-in NT Kernel Logger, converts with tracerpt, analyses in C#.
# Keep the PC idle during the capture. Default 600 s.
param([int]$Seconds = 600, [string]$Tag = 'before', [switch]$AnalyzeOnly)
. "$PSScriptRoot\lib\Common.ps1"; $root = Initialize-Workspace
$dir = Join-Path $root "baseline\$Tag"; New-Item -ItemType Directory -Force $dir | Out-Null
$etl = Join-Path $dir 'kernel.etl'; $csv = Join-Path $dir 'kernel.csv'

if (-not $AnalyzeOnly) {
    if (-not (Test-Admin)) { throw 'Measure-Dpc needs admin (NT Kernel Logger)' }
    Get-Process LatMon -ErrorAction SilentlyContinue | Stop-Process -Force   # LatencyMon holds the kernel logger
    & logman stop 'NT Kernel Logger' -ets 2>&1 | Out-Null
    Remove-Item $etl, $csv -ErrorAction SilentlyContinue
    $o = & logman start 'NT Kernel Logger' -p 'Windows Kernel Trace' '(dpc,isr,img)' -o $etl -ets -ct perf -bs 1024 -nb 128 512 2>&1
    if ($LASTEXITCODE -ne 0) { throw "logman start failed: $o" }
    Write-Output "Capturing DPC/ISR for $Seconds s - do not use the PC..."
    Start-Sleep $Seconds
    & logman stop 'NT Kernel Logger' -ets | Out-Null
    & tracerpt $etl -o $csv -of CSV -y | Out-Null
}

if (-not ('PCOptDpc' -as [type])) {
Add-Type -Language CSharp @'
using System; using System.IO; using System.Collections.Generic; using System.Globalization; using System.Text; using System.Linq;
public class PCOptDpc {
  class Mod { public ulong Base, End; public string Name; }
  class Agg { public long Count; public double MaxUs, TotalUs; public int MaxCpu; }
  static bool Hex(string s, out ulong v) { s = s.Trim(); if (s.StartsWith("0x")) s = s.Substring(2); return ulong.TryParse(s, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out v); }
  // tracerpt CSV columns: [0]event [1]type ... [11]cpu ... [16]clock(100ns) [19]InitialTime [20]Routine ; Image: [19]base [20]size, last=file
  public static string Run(string path) {
    var mods = new List<Mod>(); var raw = new List<Tuple<string,int,long,long,ulong>>(); long first = long.MaxValue, last = 0;
    using (var sr = new StreamReader(path, Encoding.UTF8, true, 1 << 20)) { string line;
      while ((line = sr.ReadLine()) != null) {
        int i = 0; while (i < line.Length && line[i] == ' ') i++;
        bool perf = string.CompareOrdinal(line, i, "PerfInfo,", 0, 9) == 0, img = string.CompareOrdinal(line, i, "Image,", 0, 6) == 0;
        if (!perf && !img) continue; var f = line.Split(','); if (f.Length < 21) continue; string type = f[1].Trim();
        if (img) { if (type != "DCStart" && type != "Load") continue; ulong b, s; if (!Hex(f[19], out b) || !Hex(f[20], out s)) continue;
          string n = f[f.Length-1].Trim().Trim('"'); int k = n.LastIndexOf('\\'); if (k >= 0) n = n.Substring(k+1); mods.Add(new Mod{Base=b, End=b+s, Name=n}); continue; }
        string kind = (type == "DPC" || type == "TimerDPC" || type == "ThreadedDPC") ? "DPC" : (type.StartsWith("ISR") ? "ISR" : null); if (kind == null) continue;
        long clock, init; int cpu; ulong r;
        if (!long.TryParse(f[16].Trim(), out clock) || !long.TryParse(f[19].Trim(), out init) || !int.TryParse(f[11].Trim(), out cpu) || !Hex(f[20], out r)) continue;
        if (clock < first) first = clock; if (clock > last) last = clock; raw.Add(Tuple.Create(kind, cpu, clock, init, r)); } }
    mods.Sort((a,b) => a.Base.CompareTo(b.Base));
    Func<ulong,string> look = a => { int lo=0, hi=mods.Count-1; while (lo<=hi) { int m=(lo+hi)/2; if (a < mods[m].Base) hi=m-1; else if (a >= mods[m].End) lo=m+1; else return mods[m].Name; } return "unknown"; };
    double[] edges = {250,500,1000,2000,4000};
    var hist = new Dictionary<string,long[]>{{"DPC",new long[6]},{"ISR",new long[6]}}; var tot = new Dictionary<string,Agg>{{"DPC",new Agg()},{"ISR",new Agg()}};
    var per = new Dictionary<string,Agg>(); var cache = new Dictionary<ulong,string>();
    foreach (var e in raw) { double us = (e.Item3 - e.Item4) / 10.0; if (us < 0 || us > 1e6) continue;
      string d; if (!cache.TryGetValue(e.Item5, out d)) { d = look(e.Item5); cache[e.Item5] = d; }
      int b = 0; while (b < 5 && us >= edges[b]) b++; hist[e.Item1][b]++;
      var t = tot[e.Item1]; t.Count++; t.TotalUs += us; if (us > t.MaxUs) { t.MaxUs = us; t.MaxCpu = e.Item2; }
      Agg a; string key = e.Item1 + "|" + d; if (!per.TryGetValue(key, out a)) { a = new Agg(); per[key] = a; } a.Count++; a.TotalUs += us; if (us > a.MaxUs) { a.MaxUs = us; a.MaxCpu = e.Item2; } }
    double dur = (last - first) / 1e7; int ncpu = Environment.ProcessorCount; var ci = CultureInfo.InvariantCulture; var sb = new StringBuilder();
    sb.AppendLine(string.Format(ci, "Trace {0:F0} s, {1} CPUs, {2} events", dur, ncpu, raw.Count));
    foreach (var k in new[]{"DPC","ISR"}) { var t = tot[k]; var h = hist[k];
      sb.AppendLine(string.Format(ci, "{0}: highest {1:F1} us (CPU {2}), count {3:N0}, time {4:F4} %", k, t.MaxUs, t.MaxCpu, t.Count, dur > 0 ? t.TotalUs/1e6/(dur*ncpu)*100 : 0));
      sb.AppendLine(string.Format(ci, "  histogram <250us {0:N0} | 250-500 {1:N0} | 500-1000 {2:N0} | 1-2ms {3:N0} | 2-4ms {4:N0} | >=4ms {5:N0}", h[0],h[1],h[2],h[3],h[4],h[5]));
      foreach (var kv in per.Where(x => x.Key.StartsWith(k + "|")).OrderByDescending(x => x.Value.MaxUs).Take(8))
        sb.AppendLine(string.Format(ci, "    {0,-26} max {1,8:F1} us  count {2,9:N0}  total {3,8:F1} ms", kv.Key.Substring(4), kv.Value.MaxUs, kv.Value.Count, kv.Value.TotalUs/1000)); }
    return sb.ToString(); }
}
'@
}
$r = [PCOptDpc]::Run($csv)
$r | Out-File (Join-Path $dir 'dpc-summary.txt') -Encoding utf8
$r
'Read: avg DPC low + no events >= 1-2 ms = good for gaming. LatencyMon-style red warnings trigger on any single DPC > ~1 ms (audio-oriented).'
