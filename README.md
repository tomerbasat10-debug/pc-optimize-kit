# pc-optimize-kit

כלי להגדרה וכיול של מחשב Windows 11 חדש לגיימינג עם השהיה נמוכה ולעבודה. כל שינוי מגובה, נרשם ביומן וניתן לביטול.
A Claude Code skill + PowerShell scripts for safe, reversible Windows 11 desktop tuning (low input lag gaming + productivity).

## מה הכלי עושה
| שלב | מה קורה | צריך אישור? |
|---|---|---|
| סריקה | חומרה, דרייברים חסרים, XMP, קצב רענון, חריץ כרטיס מסך (PCIe), אבטחה, דיסקים, שגיאות | לא, רק קריאה |
| מדידה | DPC/ISR latency (במקום LatencyMon), טמפרטורות, Cinebench, WinSAT, קצב דגימה של העכבר | התקנת כלים: כן |
| BIOS | בדיקה מתוך Windows, וצ'קליסט עם נתיבי תפריט מדויקים ללוח | אתה עושה ידנית |
| שינויים | 240 Hz, האצת עכבר, דרייברים רשמיים, הגדרות GPU להשהיה נמוכה | כן, בקבוצות |
| אפליקציות | מתקין את התוכנות הקבועות שלך מתיקייה (winget קודם, ואחרת מתקין חתום) | כן |
| יציבות ודוח | בדיקת עומס, יומן אירועים, דוח לפני/אחרי | לא |

## התקנה על מחשב חדש
1. התקן את Claude Code (האפליקציה של Claude ל-Windows, לשונית Code).
2. אחת משתי הדרכים:
   - **Plugin:** בתוך Claude Code: `/plugin marketplace add tomerbasat10-debug/pc-optimize-kit`, ואז `/plugin install pc-optimize-kit`
   - **ידני:** הורד את הריפו כ-ZIP, חלץ אותו והרץ `powershell -ExecutionPolicy Bypass -File .\install.ps1`
3. ב-Claude Code כתוב: **"תגדיר לי את המחשב"** או `/pc-optimize`

התיקייה של כל מחשב היא `C:\PCOptimize`: לוגים, גיבויים, מדידות, `journal.jsonl` ו-`FINAL-REPORT.md`.

## הסקריפטים (`skills/pc-optimize/scripts`)
| סקריפט | Admin | תפקיד |
|---|---|---|
| `Invoke-Scan.ps1` | עדיף | סריקה מלאה וממצאים לפי חומרה |
| `Get-VendorDrivers.ps1` | לא | דרייברים ו-BIOS עדכניים של יצרן הלוח (ASUS דרך API רשמי) |
| `Install-Tools.ps1` | כן | LibreHardwareMonitor+PawnIO, PresentMon, NVIDIA Profile Inspector, Cinebench, OCCT (עם אימות hash/חתימה) |
| `Measure-Baseline.ps1` | כן | מדדים במצב מנוחה, WinSAT, זמן אתחול, Cinebench |
| `Measure-Dpc.ps1` | כן | הקלטת DPC/ISR של 10 דקות וניתוח לפי דרייבר |
| `Test-Stability.ps1` | כן | טמפרטורות במנוחה ובעומס, ובדיקת WHEA וקריסות |
| `Measure-MousePolling.ps1` | לא | קצב הדגימה האמיתי של העכבר |
| `Set-Display.ps1` | לא | קצב רענון מקסימלי (Apply/Revert) |
| `Set-Mouse.ps1` | לא | כיבוי האצת עכבר (Apply/Revert) |
| `Set-GpuLatency.ps1` | כן | אופטימיזציות לחלון, NVIDIA Low Latency, G-SYNC (Apply/Revert) |
| `Install-DriverPackage.ps1` | כן | דרייבר רשמי עם גיבוי (Inf / Nvidia / Setup) |
| `Install-Apps.ps1` | כן | התוכנות הקבועות מתיקייה (Plan ואז Install) |
| `Revert-All.ps1` | כן | ביטול כל השינויים מהיומן (`-WhatIf` לתצוגה בלבד) |
| `New-Report.ps1` | לא | דוח סופי |

## עקרונות
- סריקה ומדידה בלבד, עד שאתה מאשר.
- רק מקורות רשמיים, עם אימות hash או חתימה. בלי חבילות debloat ובלי "מעדכני דרייברים".
- Defender, Windows Update, VBS ו-Secure Boot לא מכובים בלי הסבר ואישור.
- הלקחים מהפעם הראשונה נמצאים ב-`skills/pc-optimize/reference/lessons.md`.
