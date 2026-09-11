using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Management;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

// DeepSeek Harness Mini tray launcher (single exe, no console window)
// Built with PowerShell Add-Type (system .NET Framework csc), zero dependencies.
// NOTE: source must stay pure ASCII; Chinese UI strings use \uXXXX escapes
// because csc reads source with the system ANSI codepage.
//
// Portable edition rules:
//   - EVERY path is resolved from the exe directory (root), so the package
//     can be installed anywhere and moved without changes.
//   - Bundled Node lives in root\node\node.exe; falls back to PATH "node".
//   - pnpm store lives in root\.pnpm-store, never on a fixed drive letter.
//   - Process matching kills only node.exe running THIS install (root\app).
//   - Optional port argument: DshMini.exe [port]  (default 2233).
//   - DSH 0.1.5+ prints a per-process launch token URL on stdout; the tray
//     captures it (live stdout + log fallback) and always opens the panel
//     WITH the token, because the bare origin answers 401.
public class DshTray
{
    static string root;
    static string nodeExe;
    static string entry;
    static string appDir;
    static string profileDir;
    static string goodDir;
    static string logFile;
    static string url = "http://127.0.0.1:2233";
    static int port = 2233;
    // DSH 0.1.5+ gates the web UI behind a per-process random launch token and
    // prints "dsh web: http://127.0.0.1:2233/?token=<43 chars>" on stdout. The
    // tray captures that URL and opens it; a bare origin would only show the
    // 401 / enter-your-key page.
    static string panelUrl = null;
    static object panelLock = new object();
    static readonly System.Text.RegularExpressions.Regex tokenRe =
        new System.Text.RegularExpressions.Regex("https?://[^\\s\"]*\\?token=[A-Za-z0-9_\\-]+");

    static Process serverProc = null;
    static NotifyIcon trayIcon;
    static object logLock = new object();

    [STAThread]
    static void Main(string[] args)
    {
        // Optional port override: DshMini.exe 2234
        // Stop mode: DshMini.exe --stop  (kills this install's node server AND
        // its resident tray, then exits - so a fresh double click works after)
        bool stopOnly = false;
        if (args != null && args.Length > 0)
        {
            foreach (string a in args)
            {
                if (a == "--stop") stopOnly = true;
                else
                {
                    int p;
                    if (int.TryParse(a, out p) && p > 0 && p < 65536) port = p;
                }
            }
        }

        InitPaths();

        if (stopOnly)
        {
            StopServer();
            return;
        }

        bool createdNew;
        Mutex mutex = new Mutex(true, "DshMiniTray_Mutex_v1", out createdNew);
        if (!createdNew)
        {
            // Tray of THIS install is already running: open its panel and exit.
            // (If its server is down, the resident tray's menu "restart" is the
            // way back; --stop kills the resident tray too, so a plain double
            // click after --stop starts a fresh tray.)
            AppendLog("second instance: tray already running, opening panel");
            if (BrowserEnabled()) OpenBrowser();
            return;
        }

        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);

        trayIcon = new NotifyIcon();
        trayIcon.Text = "DeepSeek Harness Mini";
        Icon ic = null;
        try { ic = Icon.ExtractAssociatedIcon(Application.ExecutablePath); }
        catch { }
        if (ic == null) ic = SystemIcons.Application;
        trayIcon.Icon = ic;
        trayIcon.Visible = true;
        trayIcon.ContextMenuStrip = BuildMenu();
        trayIcon.DoubleClick += delegate { OpenBrowser(); };

        Thread t = new Thread(RunStartup);
        t.IsBackground = true;
        t.Start();

        Application.Run();

        trayIcon.Visible = false;
        trayIcon.Dispose();
        GC.KeepAlive(mutex);
    }

    static void InitPaths()
    {
        root = AppDomain.CurrentDomain.BaseDirectory;
        nodeExe = root + "node\\node.exe";
        entry = root + "app\\node_modules\\@deepseek-ai\\dsh\\lib\\bin.js";
        appDir = root + "app";
        profileDir = root + "home\\profiles\\web";
        goodDir = root + "backups\\last-good";
        logFile = root + ".tray.log";
        url = "http://127.0.0.1:" + port;

        // Ensure runtime directories exist. The launcher bat file used to
        // create these with mkdir; dsh crashes without them (mkdtemp into
        // TEMP fails when the dir is missing).
        try { Directory.CreateDirectory(root + ".temp"); } catch { }
        try { Directory.CreateDirectory(root + ".npm-cache"); } catch { }
        try { Directory.CreateDirectory(root + "home"); } catch { }
    }

    static ContextMenuStrip BuildMenu()
    {
        ContextMenuStrip m = new ContextMenuStrip();

        // "\u6253\u5f00\u9762\u677f" = open panel (starts the server when it is down)
        m.Items.Add("\u6253\u5f00\u9762\u677f", null, delegate { OpenPanel(); });
        // "\u590d\u5236\u9762\u677f\u5730\u5740(\u542b token)" = copy panel address incl. token
        m.Items.Add("\u590d\u5236\u9762\u677f\u5730\u5740(\u542b token)", null, delegate { CopyPanelUrl(); });
        // "\u91cd\u542f" = restart
        m.Items.Add("\u91cd\u542f", null, delegate { Restart(); });
        m.Items.Add(new ToolStripSeparator());

        // "\u56de\u6863\u6062\u590d" = rollback
        m.Items.Add("\u56de\u6863\u6062\u590d", null, delegate { RollbackRestart(); });

        // "\u5f00\u673a\u81ea\u542f" = autostart
        ToolStripMenuItem autoStart = new ToolStripMenuItem("\u5f00\u673a\u81ea\u542f");
        autoStart.CheckOnClick = true;
        autoStart.Checked = IsAutoStart();
        autoStart.CheckedChanged += delegate { SetAutoStart(autoStart.Checked); };
        m.Items.Add(autoStart);

        // "\u67e5\u770b\u65e5\u5fd7" = view log
        m.Items.Add("\u67e5\u770b\u65e5\u5fd7", null, delegate { ViewLog(); });
        m.Items.Add(new ToolStripSeparator());

        // "\u9000\u51fa" = exit
        m.Items.Add("\u9000\u51fa", null, delegate { ExitApp(); });

        return m;
    }

    // ---------- browser / port ----------

    // Pull the launch-token URL out of one server output line.
    static void CaptureToken(string line)
    {
        if (line == null) return;
        if (line.IndexOf("token=", StringComparison.OrdinalIgnoreCase) < 0) return;
        try
        {
            System.Text.RegularExpressions.Match m = tokenRe.Match(line);
            if (!m.Success) return;
            lock (panelLock) { panelUrl = m.Value; }
        }
        catch { }
    }

    // Fallback: recover the newest token URL from the tail of the tray log
    // (needed when the server was already running before this tray started).
    static string ScanLogForToken()
    {
        try
        {
            if (!File.Exists(logFile)) return null;
            using (FileStream fs = new FileStream(logFile, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            {
                long len = fs.Length;
                int take = (int)Math.Min(len, 200000L);
                fs.Seek(len - take, SeekOrigin.Begin);
                byte[] buf = new byte[take];
                int read = fs.Read(buf, 0, take);
                string text = System.Text.Encoding.UTF8.GetString(buf, 0, read);
                System.Text.RegularExpressions.MatchCollection ms = tokenRe.Matches(text);
                if (ms.Count > 0) return ms[ms.Count - 1].Value;
            }
        }
        catch { }
        return null;
    }

    // Wait until the server printed its token URL (lands right after the port opens).
    static void WaitToken(int timeoutMs)
    {
        int waited = 0;
        while (waited < timeoutMs)
        {
            lock (panelLock) { if (panelUrl != null) return; }
            Thread.Sleep(500);
            waited += 500;
        }
    }

    static string ResolvePanelUrl()
    {
        lock (panelLock) { if (panelUrl != null) return panelUrl; }
        string scanned = ScanLogForToken();
        if (scanned != null) { lock (panelLock) { panelUrl = scanned; } return scanned; }
        return null;
    }

    static void OpenBrowser()
    {
        string target = ResolvePanelUrl();
        bool withToken = target != null;
        if (!withToken) target = url;
        try
        {
            AppendLog("opening panel (" + (withToken ? "with launch token" : "no token found, plain origin") + ")");
            Process.Start(target);
        }
        catch (Exception ex) { AppendLog("[ERROR] open browser: " + ex.Message); }
    }

    // Menu action: open the panel, bringing the server up first when it is down.
    static void OpenPanel()
    {
        if (!IsPortOpen())
        {
            AppendLog("open panel: server down, starting it");
            lock (panelLock) { panelUrl = null; }
            StartStartupThread();
            return;
        }
        OpenBrowser();
    }

    // Menu action: copy the full panel address (token included) to the clipboard.
    static void CopyPanelUrl()
    {
        string target = ResolvePanelUrl();
        bool withToken = target != null;
        if (!withToken) target = url;
        try
        {
            Clipboard.SetText(target);
            // "\u9762\u677f\u5730\u5740\u5df2\u590d\u5236" = panel address copied
            ShowBalloon("\u9762\u677f\u5730\u5740\u5df2\u590d\u5236"
                + (withToken ? "(\u542b\u5bc6\u94a5)" : "(\u65e0\u5bc6\u94a5)"),
                withToken ? ToolTipIcon.Info : ToolTipIcon.Warning);
        }
        catch (Exception ex) { AppendLog("[ERROR] copy panel url: " + ex.Message); }
    }

    static bool IsPortOpen()
    {
        try
        {
            using (System.Net.Sockets.TcpClient c = new System.Net.Sockets.TcpClient())
            {
                IAsyncResult ar = c.BeginConnect("127.0.0.1", port, null, null);
                if (ar.AsyncWaitHandle.WaitOne(600))
                {
                    c.EndConnect(ar);
                    return true;
                }
                return false;
            }
        }
        catch { return false; }
    }

    static bool WaitPort(int timeoutMs)
    {
        int waited = 0;
        while (waited < timeoutMs)
        {
            if (IsPortOpen()) return true;
            Thread.Sleep(500);
            waited += 500;
        }
        return false;
    }

    // ---------- server lifecycle ----------

    static void StartServer()
    {
        try
        {
            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = File.Exists(nodeExe) ? nodeExe : "node";
            psi.Arguments = "\"" + entry + "\" web --host 127.0.0.1 --port " + port + " --no-open";
            psi.WorkingDirectory = appDir;
            psi.WindowStyle = ProcessWindowStyle.Hidden;
            psi.CreateNoWindow = true;
            psi.UseShellExecute = false;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;

            psi.EnvironmentVariables["DSH_HOME"] = root + "home";
            psi.EnvironmentVariables["HOME"] = root + "home";
            psi.EnvironmentVariables["npm_config_cache"] = root + ".npm-cache";
            psi.EnvironmentVariables["npm_config_store_dir"] = root + ".pnpm-store";
            psi.EnvironmentVariables["TEMP"] = root + ".temp";
            psi.EnvironmentVariables["TMP"] = root + ".temp";

            serverProc = new Process();
            serverProc.StartInfo = psi;
            serverProc.EnableRaisingEvents = true;
            serverProc.OutputDataReceived += delegate(object s, DataReceivedEventArgs e) { AppendLog(e.Data); };
            serverProc.ErrorDataReceived += delegate(object s, DataReceivedEventArgs e) { AppendLog(e.Data); };
            serverProc.Start();
            serverProc.BeginOutputReadLine();
            serverProc.BeginErrorReadLine();
            AppendLog("node started, pid=" + serverProc.Id);
        }
        catch (Exception ex)
        {
            AppendLog("[ERROR] start server: " + ex.Message);
        }
    }

    static void StopServer()
    {
        try
        {
            if (serverProc != null && !serverProc.HasExited)
            {
                serverProc.Kill();
                AppendLog("killed tracked node pid=" + serverProc.Id);
            }
        }
        catch { }
        KillHarnessNodes();
        KillSiblingTrays();
    }

    // Kill the tray window process(es) of THIS install, never this very process.
    // Without this, "--stop" would leave a resident tray whose server is dead:
    // a later double click then finds the single-instance mutex taken, exits
    // without starting anything, and the user is stuck with a dead panel.
    static void KillSiblingTrays()
    {
        try
        {
            string self = root + "DshMini.exe";
            int me = Process.GetCurrentProcess().Id;
            ManagementObjectSearcher searcher =
                new ManagementObjectSearcher("SELECT ProcessId, ExecutablePath FROM Win32_Process WHERE Name='DshMini.exe'");
            foreach (ManagementObject obj in searcher.Get())
            {
                try
                {
                    int pid = Convert.ToInt32(obj["ProcessId"]);
                    if (pid == me) continue;
                    string path = obj["ExecutablePath"] as string;
                    if (path == null) continue;
                    if (!path.Equals(self, StringComparison.OrdinalIgnoreCase)) continue;
                    Process.GetProcessById(pid).Kill();
                    AppendLog("stopped sibling tray pid=" + pid);
                }
                catch { }
            }
            searcher.Dispose();
        }
        catch (Exception ex) { AppendLog("[ERROR] stop sibling trays: " + ex.Message); }
    }

    // Kill only node.exe whose command line contains THIS install's app dir.
    // Other dsh installs (or unrelated node apps) are never touched.
    static void KillHarnessNodes()
    {
        try
        {
            string match = root + "app";
            ManagementObjectSearcher searcher =
                new ManagementObjectSearcher("SELECT ProcessId, CommandLine FROM Win32_Process WHERE Name='node.exe'");
            foreach (ManagementObject obj in searcher.Get())
            {
                string cmd = obj["CommandLine"] as string;
                if (cmd != null && cmd.IndexOf(match, StringComparison.OrdinalIgnoreCase) >= 0)
                {
                    try
                    {
                        Process p = Process.GetProcessById(Convert.ToInt32(obj["ProcessId"]));
                        p.Kill();
                        AppendLog("killed harness node pid=" + p.Id);
                    }
                    catch { }
                }
            }
            searcher.Dispose();
        }
        catch (Exception ex)
        {
            AppendLog("[ERROR] kill nodes: " + ex.Message);
        }
    }

    static bool BrowserEnabled()
    {
        return Environment.GetEnvironmentVariable("DSH_NO_BROWSER") != "1";
    }

    static void RunStartup()
    {
        try
        {
            if (IsPortOpen())
            {
                AppendLog("port already in use, recovering token from log and opening browser only");
                if (BrowserEnabled()) OpenBrowser();
                return;
            }

            for (int attempt = 0; attempt < 2; attempt++)
            {
                AppendLog("starting server (attempt " + (attempt + 1) + ")");
                lock (panelLock) { panelUrl = null; }   // every server run gets a fresh token
                StartServer();
                if (!WaitPort(60000))
                {
                    AppendLog("[ERROR] port not ready after 60s");
                    break;
                }
                AppendLog("port ready, waiting for launch token");
                if (BrowserEnabled())
                {
                    WaitToken(25000);
                    OpenBrowser();
                }
                Thread.Sleep(15000);
                if (IsPortOpen())
                {
                    AppendLog("stable, saving last-good snapshot");
                    SaveGood();
                    return;
                }
                AppendLog("[WARN] server died after start, restoring last-good");
                StopServer();
                if (!RestoreGood())
                {
                    AppendLog("[ERROR] no last-good backup, cannot auto-restore");
                    break;
                }
                Thread.Sleep(1000);
            }
        }
        catch (Exception ex)
        {
            AppendLog("[ERROR] startup: " + ex.Message);
        }
    }

    // ---------- snapshot / rollback ----------

    static void SaveGood()
    {
        try
        {
            if (!Directory.Exists(goodDir)) Directory.CreateDirectory(goodDir);
            CopyIfExists(profileDir + "\\package.json", goodDir + "\\package.json");
            CopyIfExists(profileDir + "\\cordis.patch.yml", goodDir + "\\cordis.patch.yml");
            CopyIfExists(profileDir + "\\pnpm-lock.yaml", goodDir + "\\pnpm-lock.yaml");
        }
        catch (Exception ex) { AppendLog("[ERROR] save good: " + ex.Message); }
    }

    static bool RestoreGood()
    {
        try
        {
            if (!File.Exists(goodDir + "\\package.json")) return false;
            CopyIfExists(goodDir + "\\package.json", profileDir + "\\package.json");
            CopyIfExists(goodDir + "\\cordis.patch.yml", profileDir + "\\cordis.patch.yml");
            CopyIfExists(goodDir + "\\pnpm-lock.yaml", profileDir + "\\pnpm-lock.yaml");
            return true;
        }
        catch (Exception ex) { AppendLog("[ERROR] restore good: " + ex.Message); return false; }
    }

    static void CopyIfExists(string src, string dst)
    {
        if (File.Exists(src)) File.Copy(src, dst, true);
    }

    // ---------- menu actions ----------

    static void Restart()
    {
        StopServer();
        // wait until the port is actually released (up to 10s)
        for (int i = 0; i < 20 && IsPortOpen(); i++) Thread.Sleep(500);
        lock (panelLock) { panelUrl = null; }
        StartStartupThread();
    }

    static void RollbackRestart()
    {
        StopServer();
        Thread.Sleep(500);
        if (RestoreGood())
            ShowBalloon("\u5df2\u6062\u590d\u56de\u6863\u70b9\uff0c\u6b63\u5728\u91cd\u542f", ToolTipIcon.Info);
        else
            ShowBalloon("\u6ca1\u6709\u53ef\u7528\u7684\u56de\u6863\u70b9", ToolTipIcon.Warning);
        lock (panelLock) { panelUrl = null; }
        StartStartupThread();
    }

    static void StartStartupThread()
    {
        Thread t = new Thread(RunStartup);
        t.IsBackground = true;
        t.Start();
    }

    static void ExitApp()
    {
        StopServer();
        Application.Exit();
    }

    static void ViewLog()
    {
        try
        {
            if (!File.Exists(logFile)) File.WriteAllText(logFile, "");
            Process.Start("notepad.exe", "\"" + logFile + "\"");
        }
        catch (Exception ex) { AppendLog("[ERROR] view log: " + ex.Message); }
    }

    static void ShowBalloon(string text, ToolTipIcon icon)
    {
        try { trayIcon.ShowBalloonTip(2000, "DeepSeek Harness Mini", text, icon); }
        catch { }
    }

    // ---------- autostart (HKCU Run) ----------

    static bool IsAutoStart()
    {
        try
        {
            using (RegistryKey key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", false))
            {
                return key != null && key.GetValue("DeepSeek Harness Mini") != null;
            }
        }
        catch { return false; }
    }

    static void SetAutoStart(bool on)
    {
        try
        {
            using (RegistryKey key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", true))
            {
                if (key == null) return;
                if (on)
                    key.SetValue("DeepSeek Harness Mini", Application.ExecutablePath);
                else
                    key.DeleteValue("DeepSeek Harness Mini", false);
            }
        }
        catch (Exception ex) { AppendLog("[ERROR] autostart: " + ex.Message); }
    }

    // ---------- log ----------

    static void AppendLog(string line)
    {
        if (line == null) return;
        CaptureToken(line);
        try
        {
            lock (logLock)
            {
                File.AppendAllText(logFile,
                    DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + line + Environment.NewLine);
            }
        }
        catch { }
    }
}
