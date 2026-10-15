using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Windows.Forms;
using OpenProjectTray;

class Launcher {
    [STAThread] static int Main(string[] args) {
        bool background = Array.IndexOf(args, "--background") >= 0;
        bool startup = Array.IndexOf(args, "--startup") >= 0;
        bool acquired = false;
        using (var mutex = new Mutex(false, "Local\\" + BridgeClient.PipeName + ".Launch")) {
            try {
                try { acquired = mutex.WaitOne(15000); } catch (AbandonedMutexException) { acquired = true; }
                if (!acquired) throw new TimeoutException("Приложение уже запускается. Повторите позже.");
                bool alive = false;
                try { BridgeClient.Request("status"); alive = true; } catch { }
                if (!alive) {
                    string folder = AppDomain.CurrentDomain.BaseDirectory;
                    string script = Path.Combine(folder, "OpenProject-Tray.ps1");
                    if (!File.Exists(script)) throw new FileNotFoundException("Не найден скрипт приложения", script);
                    var info = new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell/v1.0/powershell.exe"));
                    info.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File \"" + script + "\" -Background" + (startup ? " -Startup" : "");
                    info.WorkingDirectory = folder; info.UseShellExecute = false; info.CreateNoWindow = true; info.WindowStyle = ProcessWindowStyle.Hidden;
                    using (var child = Process.Start(info)) {
                        for (int i=0; i<80; i++) {
                            if (child.HasExited) throw new Exception("Контроллер завершился. Проверьте logs/tray-startup-error.log.");
                            try { BridgeClient.Request("status"); alive = true; break; } catch { Thread.Sleep(150); }
                        }
                    }
                    if (!alive) throw new TimeoutException("Контроллер не ответил после запуска.");
                }
                // Never retry an activation: response loss does not mean it was not accepted.
                if (!background && !startup) BridgeClient.Request("activate");
                return 0;
            } catch (Exception e) {
                if (!background) MessageBox.Show(e.Message, "OpenProject Tray", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            } finally { if (acquired) mutex.ReleaseMutex(); }
        }
    }
}
