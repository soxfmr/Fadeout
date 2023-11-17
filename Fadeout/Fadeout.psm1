$_defaultDelay = 2000
$_defaultConfigName = "config.xml"
$_defaultConfigProperties = @{
    'Delay' = $_defaultDelay
}

Add-Type -TypeDefinition @'
    using System;
    using System.Drawing;
    using System.Runtime;
    using System.Security;
    using System.Diagnostics;
    using System.Windows.Forms;
    using System.Runtime.InteropServices;
    using System.Runtime.CompilerServices;

    namespace Fadeout {

        public static class User32 {
            public const int WH_MOUSE_LL = 14;

            public delegate IntPtr HookProc(int code, IntPtr wParam, IntPtr lParam);

            [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
            public static extern IntPtr SetWindowsHookEx(int idHook, HookProc lpfn, IntPtr hMod, uint dwThreadId);
        
            [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
            public static extern bool UnhookWindowsHookEx(IntPtr hhk);
        
            [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
            public static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);
        
            [DllImport("user32.dll", CharSet = CharSet.Auto)]
            public static extern int ShowCursor(int bShow);
        }

        public static class Kernel32 {
            [DllImport("kernel32.dll")]
            public static extern uint GetLastError();
            
            [DllImport("kernel32.dll")]
            public static extern uint GetCurrentThreadId();
        }

        public static class Logging {
            
            private static string applicationName;
            public static string ApplicationName {
                get { return applicationName; }
                set {
                    string newAppName = value;
                    string oldAppName = applicationName;

                    if (String.IsNullOrEmpty(newAppName)) {
                        throw new Exception("the application name must not be empty");
                    }
                    
                    if (oldAppName != newAppName && ! String.IsNullOrEmpty(oldAppName)) {
                        try {
                            if (EventLog.SourceExists(oldAppName)) {
                                EventLog.DeleteEventSource(oldAppName);
                            }
                        } catch(Exception) {}
                    }

                    bool sourceExists = false;
                    try {
                        sourceExists = EventLog.SourceExists(newAppName);
                    } catch(Exception) {
                        sourceExists = false;
                    }

                    if (! sourceExists) {
                        EventLog.CreateEventSource(newAppName, "Application");
                    }
                    
                    applicationName = newAppName;
                }
            }

            public enum LoggingType {
                Info         = EventLogEntryType.Information,
                Error        = EventLogEntryType.Error
            }

            public static void Info(string message) {
                Log(message, LoggingType.Info);
            }

            public static void Error(string message) {
                Log(message, LoggingType.Error);
            }
        
            public static void Log(string message, LoggingType t) {
                EventLog.WriteEntry(applicationName, message, (EventLogEntryType)(t), 1000);
            }

        }

        public class MouseActionConfig {
            public int MouseIdleCheckInterval;
        }

        public class MouseActionManager {

            private static readonly object cursorShowLock = new object();

            private IntPtr hHandle;
			private User32.HookProc lowLevelMouseProc;
            private Timer mouseIdleTimer;

            private ulong mouseActionCounter = 0;
            private ulong preMouseActionCounter = 0;
            private MouseActionConfig config;
            
            private static Point screenPos;
            private static Rectangle screenClip;
            private static Point invisiblePos;

            private bool cursorVisibility;
            private int cursorReactive;

            public MouseActionManager(MouseActionConfig cfg) {
                config = cfg;
                initPos();
            }

            private void initPos() {
                cursorVisibility = true;
                screenClip = Cursor.Clip;
                screenPos = Cursor.Position;

                Screen screen = Screen.FromPoint(screenPos);
                Rectangle bounds = screen.Bounds;
                invisiblePos = new Point(bounds.Width, bounds.Height);
            }

            public bool Start() {
                if (! OnStart()) {
                    Logging.Error(String.Format("Cannot setup windows mouse hook, error code: 0x{0:X8}", Kernel32.GetLastError()));
                    return false;
                }

                Logging.Info("Windows mouse hook is installed");

                return true;
            }

            protected bool OnStart() {
                // Mouse hook
                lowLevelMouseProc = new User32.HookProc(LowLevelMouseProc);
                hHandle = User32.SetWindowsHookEx(User32.WH_MOUSE_LL, lowLevelMouseProc, IntPtr.Zero, 0);
                if (hHandle == IntPtr.Zero) {
                    return false;
                }

                // Mouse counter timer
                mouseIdleTimer = new Timer();
                mouseIdleTimer.Tick += new EventHandler(TimerCallback);
                mouseIdleTimer.Interval = config.MouseIdleCheckInterval;
                mouseIdleTimer.Start();

                return true;
            }

            public void OnExit(Object sender, EventArgs e) {
                if (hHandle != IntPtr.Zero) {
                    User32.UnhookWindowsHookEx(hHandle);
                    hHandle = IntPtr.Zero;
                }

                if (mouseIdleTimer != null) {
                    mouseIdleTimer.Stop();
                }
            }

            protected IntPtr LowLevelMouseProc(int nCode, IntPtr wParam, IntPtr lParam) {
                if (nCode >= 0) {
                    mouseActionCounter++;
                    
                    if (ShouldReleaseCapture()) {
                        ReleaseCapture();
                        // Console.WriteLine("Screen recovered, w:{0}, h:{1}", screenClip.Width, screenClip.Height);
                    }
                    
                    if (! cursorVisibility) {
                        SetCapture();
                        ShowCursor(true);

                        mouseIdleTimer.Enabled = true;
                        
                        // Console.WriteLine("Cursor reactived, w:{0}, h:{1}", screenClip.Width, screenClip.Height);
                    }
                }

                if (hHandle != IntPtr.Zero) {
                    return User32.CallNextHookEx(hHandle, nCode, wParam, lParam);
                }

                return IntPtr.Zero;
            }

            protected void TimerCallback(Object obj, EventArgs eventArg) {
                if (cursorVisibility && mouseActionCounter == preMouseActionCounter) {
                    ShowCursor(false);
                    mouseIdleTimer.Enabled = false;
                }
                preMouseActionCounter = mouseActionCounter;
            }

            [MethodImpl(MethodImplOptions.AggressiveInlining)]
            protected bool ShouldReleaseCapture() {
                return (cursorReactive & 1) != 0;
            }

            [MethodImpl(MethodImplOptions.AggressiveInlining)]
            protected void ReleaseCapture() {
                Cursor.Clip = screenClip;
                cursorReactive &= 0;
            }

            [MethodImpl(MethodImplOptions.AggressiveInlining)]
            protected void SetCapture() {
                screenClip = Cursor.Clip;
                Cursor.Clip = new Rectangle(screenPos, new Size(1, 1));
                cursorReactive |= 1;
            }

            protected void ShowCursor(bool show) {
                lock (cursorShowLock) {
                    if (show) {
                        Cursor.Position = screenPos;
                        // Console.WriteLine("shiw - x:{0}, y:{1}", screenPos.X, screenPos.Y);
                    } else {
                        screenPos = Cursor.Position;
                        Cursor.Position = invisiblePos;
                        // Console.WriteLine("hise - x:{0}, y:{1}", screenPos.X, screenPos.Y);
                    }
                    
                    cursorVisibility = show;
                }
            }
        }

        public class FadeoutApplication {
            
            public static void Run(MouseActionConfig config) {
                MouseActionManager manager = new MouseActionManager(config);
                Application.ApplicationExit += new EventHandler(manager.OnExit);

                if (! manager.Start()) {
                    Logging.Error("Program exited abnormally.");
                    Application.Exit();
                }

                Application.Run();
            }

        }
    }
'@ -ReferencedAssemblies @("System.Windows.Forms", "System.Drawing")

function Get-FadeoutConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string] $configFile,

        [Parameter(Mandatory = $true)]
        [hashtable] $defaultProperties
    )
    
    $config = $null

    # Load the config file
    if (-not $configFile.Trim().Equals("")) {
        try {
            [xml] $XMLConfig = Get-Content -Path $configFile -ErrorAction Stop
            if ($XMLConfig -is [xml]) {
                $config = $XMLConfig.Config
            }
        } catch {
            # Write-Host "config file is invalid, load the default properties"
        }
    }

    if ($config -eq $null) {
        $config = New-Object -Type PSObject -Property $defaultProperties
    }

    return $config
}

<#
    .Synopsis
    Hides the idle mouse cursor automatically.

    .Description
    Hides the idle mouse cursor automatically.

    .Parameter Delay
    The minimum delay time in millionseconds to hide the mouse cursor after the cursor is idle.
    Higher value would tend to consume more CPU time, the default value is 2000.

    .Example
    Start-Fadeout

    .Example
    Start-Fadeout -Delay 1000

    .Example
    Start-Fadeout -ConfigFile C:\Fadeout\config.xml
#>
function Mount-Fadeout {
    param(
        [int] $Delay,

        [string] $ConfigFile = $_defaultConfigName
    )
    
    # Load the config file
    $config = Get-FadeoutConfig -ConfigFile $ConfigFile -DefaultProperties $_defaultConfigProperties

    # Configs are loaded in following priority:
    # 1. command line
    # 2. config file
    # 3. application default value
    if ($Delay -eq 0) {
        $Delay = $config.Delay
    }

    # Create a new mouse action config
    $mouseActionConfig = New-Object -TypeName Fadeout.MouseActionConfig -Property @{ MouseIdleCheckInterval = $Delay }

    # Start the application
    [Fadeout.Logging]::ApplicationName = "Fadeout"
    [Fadeout.FadeoutApplication]::Run($mouseActionConfig)
}

Export-ModuleMember -Function Mount-Fadeout

