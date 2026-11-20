# Measure-MousePolling.ps1 - READ-ONLY. User moves the mouse in fast circles for -Seconds; reports real report rate per device.
# Run with:  powershell -STA -File Measure-MousePolling.ps1 -Seconds 10
param([int]$Seconds = 10)
. "$PSScriptRoot\lib\Common.ps1"; $root = Initialize-Workspace
if (-not ('PCOptRawMouse' -as [type])) {
Add-Type -ReferencedAssemblies System.Windows.Forms -Language CSharp @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Windows.Forms; using System.Diagnostics;
public class PCOptRawMouse : Form {
  [StructLayout(LayoutKind.Sequential)] struct RID { public ushort Page, Usage; public uint Flags; public IntPtr Target; }
  [StructLayout(LayoutKind.Sequential)] struct HDR { public uint Type, Size; public IntPtr Device, WParam; }
  [DllImport("user32.dll")] static extern bool RegisterRawInputDevices(RID[] d, uint n, uint sz);
  [DllImport("user32.dll")] static extern uint GetRawInputData(IntPtr h, uint cmd, IntPtr data, ref uint size, uint hsz);
  public Dictionary<IntPtr, List<long>> Reports = new Dictionary<IntPtr, List<long>>();
  Stopwatch sw = Stopwatch.StartNew();
  protected override void OnHandleCreated(EventArgs e) { base.OnHandleCreated(e);
    var r = new RID[1]; r[0].Page = 1; r[0].Usage = 2; r[0].Flags = 0x100; r[0].Target = Handle;
    RegisterRawInputDevices(r, 1, (uint)Marshal.SizeOf(typeof(RID))); }
  protected override void WndProc(ref Message m) {
    if (m.Msg == 0x00FF) { uint size = 0; uint hs = (uint)Marshal.SizeOf(typeof(HDR));
      GetRawInputData(m.LParam, 0x10000003, IntPtr.Zero, ref size, hs);
      IntPtr buf = Marshal.AllocHGlobal((int)size);
      try { if (GetRawInputData(m.LParam, 0x10000003, buf, ref size, hs) == size) { var h = (HDR)Marshal.PtrToStructure(buf, typeof(HDR));
        List<long> l; if (!Reports.TryGetValue(h.Device, out l)) { l = new List<long>(); Reports[h.Device] = l; } l.Add(sw.ElapsedTicks); } }
      finally { Marshal.FreeHGlobal(buf); } }
    base.WndProc(ref m); }
  public static string Measure(int seconds) {
    var f = new PCOptRawMouse(); f.ShowInTaskbar = false; f.Opacity = 0; f.Show();
    var t = new Timer(); t.Interval = seconds * 1000; t.Tick += (s, e) => { t.Stop(); f.Close(); }; t.Start();
    Application.Run(f);
    var sb = new System.Text.StringBuilder(); double fr = Stopwatch.Frequency;
    foreach (var kv in f.Reports) { var ev = kv.Value; if (ev.Count < 20) continue;
      int peak = 0; int j = 0; for (int i = 0; i < ev.Count; i++) { while (ev[i] - ev[j] > fr) j++; peak = Math.Max(peak, i - j + 1); }
      var gaps = new List<double>(); for (int i = 1; i < ev.Count; i++) { double g = (ev[i]-ev[i-1]) / fr * 1000; if (g < 20) gaps.Add(g); }
      gaps.Sort(); double med = gaps.Count > 0 ? gaps[gaps.Count/2] : 0;
      sb.AppendLine(string.Format("device 0x{0:X}: reports {1}, peak {2}/s, median interval {3:F3} ms (~{4:F0} Hz)", kv.Key.ToInt64(), ev.Count, peak, med, med > 0 ? 1000/med : 0)); }
    return sb.Length > 0 ? sb.ToString() : "No mouse movement captured - move the mouse continuously during the test.";
  }
}
'@
}
"Move the mouse in fast circles for $Seconds seconds..."
$r = [PCOptRawMouse]::Measure($Seconds)
$r; $r | Out-File (Join-Path $root 'baseline\mouse-polling.txt') -Encoding utf8
"Guide: ~125 Hz = 8 ms between reports (raise to 1000 Hz in the mouse software); 1000 Hz = standard for gaming."
