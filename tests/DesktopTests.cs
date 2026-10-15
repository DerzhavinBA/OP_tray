using System;
using System.IO;
using System.Drawing;
using System.Threading;
using OpenProjectTray;
class DesktopTests {
    static int count;
    static void Check(bool condition, string message) { if (!condition) throw new Exception(message); Console.WriteLine("PASS " + message); count++; }
    static int Main(string[] args) {
        try {
            string pipe = "OpenProjectTray.Test." + Guid.NewGuid().ToString("N");
            using (var server = new BridgeServer(pipe)) {
                server.Publish("Stopped", false, "", "");
                Thread.Sleep(100);
                if(server.LastFailure != null) throw new Exception(server.LastFailure);
                try { Check(BridgeClient.Request(pipe, "status", 2000).Contains("Stopped"), "status without WSL"); }
                catch { Console.Error.WriteLine("Server: " + (server.LastFailure ?? "waiting; no server error")); throw; }
                Check(BridgeClient.Request(pipe, "activate", 2000).Contains("accepted"), "first activation accepted");
                Check(BridgeClient.Request(pipe, "activate", 2000).Contains("busy"), "duplicate activation rejected");
                server.Publish("Stopped", false, "", "");
                Check(BridgeClient.Request(pipe, "activate", 2000).Contains("busy"), "status publication cannot release pending activation");
                Check(server.TakeActivation(), "activation delivered once");
                Check(!server.TakeActivation(), "no duplicate delivery");
                server.Publish("Starting", true, "restart-migrate", "");
                Check(BridgeClient.Request(pipe, "activate", 2000).Contains("busy"), "running operation rejects activation");
                server.Publish("Error", false, "", "migration failed");
                Check(BridgeClient.Request(pipe, "status", 2000).Contains("migration failed"), "error shared with client");
                Check(BridgeClient.Request(pipe, "unknown", 2000).Contains("invalid"), "unknown commands rejected");
            }
            Check(ActivationPolicy.Action(false, false) == "start", "stopped starts");
            Check(ActivationPolicy.Action(true, false) == "restart-migrate", "running migrates");
            Check(ActivationPolicy.Action(true, true) == "", "busy does nothing");
            var defaults = ButtonSettings.Parse("{}");
            Check(defaults.LogoSize == 85 && defaults.MarkerSize == 20, "button defaults");
            var extremes = ButtonSettings.Parse("{\"logoSize\":900,\"markerSize\":-3}");
            Check(extremes.LogoSize == 100 && extremes.MarkerSize == 8, "size clamping");
            Check(defaults.LogoSize == 85, "settings independent across buttons");
            Check(ButtonSettings.DisplayState("Error", true) == "Error", "stale busy controller shows error");
            var styled=ButtonSettings.Parse("{\"iconStyle\":\"orbit\",\"markerPosition\":\"top-left\",\"glow\":200,\"cornerRadius\":90}");
            Check(styled.Glow==100 && styled.CornerRadius==50 && styled.IconStyle=="orbit" && styled.MarkerPosition=="top-left","appearance settings clamp and parse");
            var invalid=ButtonSettings.Parse("{\"iconStyle\":\"unknown\",\"markerPosition\":\"elsewhere\"}");
            Check(invalid.IconStyle=="classic" && invalid.MarkerPosition=="bottom-right","unknown styles use compatible defaults");
            string iconPath=Path.Combine(args[0],"OpenProject.ico");
            foreach(string position in new[]{"top-left","top-right","bottom-left","bottom-right"}) {
                var setting=new ButtonSettings {MarkerPosition=position,Glow=100};
                using(var bmp=ButtonRenderer.Render(iconPath,"Offline",setting,0)) {
                    int x=position.EndsWith("left")?20:124,y=position.StartsWith("top")?20:124;
                    Check(bmp.GetPixel(x,y).ToArgb()==Color.Black.ToArgb(),"offline marker is black at "+position);
                }
            }
            var orbit=new ButtonSettings {IconStyle="orbit"};
            Check(ButtonRenderer.DataUrl(iconPath,"Running",orbit,0)!=ButtonRenderer.DataUrl(iconPath,"Running",orbit,6),"orbit animation changes image");
            Check(ButtonRenderer.DataUrl(iconPath,"Running",defaults,0)==ButtonRenderer.DataUrl(iconPath,"Running",defaults,6),"classic stays static");
            Check(ButtonRenderer.DataUrl(iconPath,"Running",defaults)!=ButtonRenderer.DataUrl(iconPath,"Running",new ButtonSettings{CornerRadius=50}),"rounding changes classic tile");
            Check(ButtonRenderer.DataUrl(iconPath,"Running",defaults)!=ButtonRenderer.DataUrl(iconPath,"Running",new ButtonSettings{Glow=100}),"glow changes active marker");
            Check(ButtonRenderer.DataUrl(iconPath,"Offline",defaults)==ButtonRenderer.DataUrl(iconPath,"Offline",new ButtonSettings{Glow=100}),"offline marker never glows");
            using(var gallery=new Bitmap(576,144)) using(var graphics=Graphics.FromImage(gallery)) {
                int column=0;
                foreach(string style in new[]{"classic","tile","minimal","orbit"}) {
                    using(var bmp=ButtonRenderer.Render(iconPath,"Running",new ButtonSettings{IconStyle=style,CornerRadius=22,Glow=70},4)) graphics.DrawImage(bmp,column++*144,0);
                }
                gallery.Save(Path.Combine(args[0],"build/obj/icon-gallery.png"));
            }
            foreach (int logo in new [] {30,85,100}) foreach (int marker in new [] {8,20,35}) {
                using (var bmp = ButtonRenderer.Render(Path.Combine(args[0], "OpenProject.ico"), "Running", logo, marker)) {
                    Check(bmp.Width == 144 && bmp.Height == 144, "render " + logo + "/" + marker);
                    Check(bmp.GetPixel(143,143).A == 255, "opaque background at edge");
                    bmp.Save(Path.Combine(args[0], "build/obj/preview-" + logo + "-" + marker + ".png"));
                }
            }
            string sandbox = Path.Combine(args[0], "build/obj/install-test-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(sandbox);
            string other = Path.Combine(sandbox, "other.sdPlugin"); Directory.CreateDirectory(other);
            File.WriteAllText(Path.Combine(other,"keep"),"untouched");
            string package = Path.Combine(args[0], "dist/OpenProjectTray-portable/plugin/com.openproject.tray.sdPlugin");
            string exe = Path.Combine(args[0], "dist/OpenProjectTray-portable/OpenProjectTray.exe");
            string target = PluginInstaller.Install(package, sandbox, exe);
            Check(File.Exists(Path.Combine(target,"bin/OpenProjectPlugin.exe")), "plugin installed");
            Check(File.ReadAllText(Path.Combine(target,"connection.json")).Contains("exePath"), "application path supplied");
            PluginInstaller.Install(package, sandbox, exe);
            Check(File.ReadAllText(Path.Combine(other,"keep")) == "untouched", "update preserves other plugins");
            bool locked = false;
            using (var file = new FileStream(Path.Combine(target,"bin/OpenProjectPlugin.exe"), FileMode.Open, FileAccess.Read, FileShare.None)) {
                try { PluginInstaller.Install(package, sandbox, exe); } catch (IOException) { locked = true; }
            }
            Check(locked && File.Exists(Path.Combine(target,"manifest.json")), "locked update preserves old installation");
            bool nested=false;
            try { PluginInstaller.Install(package,Path.Combine(package,"static"),exe); } catch(IOException) { nested=true; }
            Check(nested,"install inside source package rejected");
            bool incomplete=false;
            try { PluginInstaller.Install(other,sandbox,exe); } catch(IOException) { incomplete=true; }
            Check(incomplete && File.Exists(Path.Combine(target,"manifest.json")),"incomplete package leaves existing plugin intact");
            string occupied=Path.Combine(sandbox,"not-a-folder");File.WriteAllText(occupied,"keep");
            bool invalidParent=false;
            try { PluginInstaller.Install(package,occupied,exe); } catch(IOException) { invalidParent=true; }
            Check(invalidParent && File.ReadAllText(occupied)=="keep","invalid destination preserves existing file");
            Console.WriteLine("Passed: " + count); return 0;
        } catch (Exception e) { Console.Error.WriteLine(e); return 1; }
    }
}
