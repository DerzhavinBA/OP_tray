using System;
using System.IO;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Collections.Generic;
using System.Web.Script.Serialization;

namespace OpenProjectTray {
    public sealed class ButtonSettings {
        public static string DisplayState(string state, bool busy) { return state == "Error" ? "Error" : busy ? "Starting" : state; }
        public int LogoSize = 85, MarkerSize = 20;
        public int Glow = 0, CornerRadius = 0;
        public string IconStyle = "classic", MarkerPosition = "bottom-right";
        public string VisualKey { get { return LogoSize+":"+MarkerSize+":"+Glow+":"+CornerRadius+":"+IconStyle+":"+MarkerPosition; } }
        static string Choice(Dictionary<string,object> map, string key, string fallback, string[] choices) {
            object value; string text=map.TryGetValue(key,out value)?Convert.ToString(value):fallback;
            return Array.IndexOf(choices,text)>=0 ? text : fallback;
        }
        public string ExePath = "";
        static int Number(Dictionary<string,object> map, string key, int fallback, int low, int high) {
            object value; int n;
            return map.TryGetValue(key, out value) && Int32.TryParse(Convert.ToString(value), out n) ? Math.Max(low, Math.Min(high,n)) : fallback;
        }
        public static ButtonSettings Parse(string json) {
            var map = new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(json) ?? new Dictionary<string,object>();
            var settings = new ButtonSettings();
            settings.LogoSize = Number(map,"logoSize",85,30,100);
            settings.MarkerSize = Number(map,"markerSize",20,8,35);
            settings.Glow = Number(map,"glow",0,0,100);
            settings.CornerRadius = Number(map,"cornerRadius",0,0,50);
            settings.IconStyle = Choice(map,"iconStyle","classic",new[]{"classic","tile","minimal","orbit"});
            settings.MarkerPosition = Choice(map,"markerPosition","bottom-right",new[]{"top-left","top-right","bottom-left","bottom-right"});
            object path; if(map.TryGetValue("exePath", out path)) settings.ExePath = Convert.ToString(path);
            return settings;
        }
    }
    public static class ButtonRenderer {
        public static Bitmap LoadLogo(string iconPath) {
            byte[] bytes=File.ReadAllBytes(iconPath);
            if(bytes.Length<6) throw new IOException("Invalid icon");
            int count=BitConverter.ToUInt16(bytes,4), best=-1, width=0;
            for(int i=0;i<count;i++) {
                int entry=6+i*16;
                if(entry+16>bytes.Length) throw new IOException("Invalid icon directory");
                int w=bytes[entry]==0 ? 256 : bytes[entry];
                if(w>width) { width=w; best=entry; }
            }
            if(best<0) throw new IOException("Empty icon");
            uint size=BitConverter.ToUInt32(bytes,best+8), offset=BitConverter.ToUInt32(bytes,best+12);
            if((long)offset+size>bytes.Length) throw new IOException("Invalid icon frame");
            // The supplied ICO has PNG frames that Icon.ToBitmap cannot decode on Framework.
            using(var stream=new MemoryStream(bytes,(int)offset,(int)size)) using(var image=Image.FromStream(stream)) return new Bitmap(image);
        }
        public static Bitmap Render(string iconPath, string state, int logoSize, int markerSize) {
            return Render(iconPath,state,new ButtonSettings {LogoSize=logoSize,MarkerSize=markerSize},0);
        }
        static GraphicsPath Rounded(RectangleF rect, float radius) {
            var path=new GraphicsPath();
            if(radius<=0) { path.AddRectangle(rect); return path; }
            float d=Math.Min(radius*2,Math.Min(rect.Width,rect.Height));
            path.AddArc(rect.X,rect.Y,d,d,180,90);path.AddArc(rect.Right-d,rect.Y,d,d,270,90);
            path.AddArc(rect.Right-d,rect.Bottom-d,d,d,0,90);path.AddArc(rect.X,rect.Bottom-d,d,d,90,90);path.CloseFigure();return path;
        }
        public static Color StateColor(string state) {
            return state=="Offline" ? Color.Black : state=="Running" ? Color.FromArgb(46,204,64) : state=="Starting" ? Color.FromArgb(240,180,20) : state=="Stopped" ? Color.FromArgb(150,150,150) : Color.FromArgb(230,50,50);
        }
        public static Bitmap Render(string iconPath, string state, ButtonSettings settings, int frame) {
            var bmp = new Bitmap(144,144);
            using(var g = Graphics.FromImage(bmp)) using(var logo = LoadLogo(iconPath)) {
                g.Clear(Color.FromArgb(25,27,32)); g.SmoothingMode = SmoothingMode.AntiAlias; g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                float size = 144 * Math.Max(30,Math.Min(100,settings.LogoSize)) / 100f;
                float ratio = Math.Min(size/logo.Width,size/logo.Height);
                float w = logo.Width*ratio, h = logo.Height*ratio;
                var rect=new RectangleF((144-w)/2,(144-h)/2,w,h);
                using(var shape=Rounded(rect,size*settings.CornerRadius/100f)) {
                    var saved=g.Save();g.SetClip(shape);
                    if(settings.IconStyle=="classic") {
                        // Extend the brand tile beneath the ICO's transparent padding so rounding is visible.
                        using(var fill=new SolidBrush(logo.GetPixel(logo.Width/4,logo.Height/4))) g.FillRectangle(fill,rect);
                        g.DrawImage(logo,rect);
                    }
                    else {
                        if(settings.IconStyle=="tile") {
                            using(var gradient=new LinearGradientBrush(rect,Color.FromArgb(54,166,236),Color.FromArgb(15,60,145),45f)) g.FillRectangle(gradient,rect);
                            using(var shine=new Pen(Color.FromArgb(70,255,255,255),2)) g.DrawLine(shine,rect.X+8,rect.Y+2,rect.Right-8,rect.Y+2);
                        } else {
                            using(var fill=new SolidBrush(settings.IconStyle=="minimal"?Color.FromArgb(35,42,53):Color.FromArgb(17,35,61))) g.FillRectangle(fill,rect);
                        }
                        using(var font=new Font("Segoe UI",size*(settings.IconStyle=="orbit"?0.29f:0.37f),FontStyle.Bold,GraphicsUnit.Pixel))
                        using(var format=new StringFormat {Alignment=StringAlignment.Center,LineAlignment=StringAlignment.Center})
                        using(var ink=new SolidBrush(settings.IconStyle=="minimal"?Color.FromArgb(92,192,255):Color.White)) g.DrawString("OP",font,ink,rect,format);
                        if(settings.IconStyle=="orbit") {
                            float inset=size*0.10f;
                            var ring=new RectangleF(rect.X+inset,rect.Y+inset,size-2*inset,size-2*inset);
                            using(var track=new Pen(Color.FromArgb(40,126,173),size*0.025f)) g.DrawEllipse(track,ring);
                            using(var arc=new Pen(Color.FromArgb(91,216,255),size*0.035f)) { arc.StartCap=LineCap.Round;arc.EndCap=LineCap.Round;g.DrawArc(arc,ring,(frame%24)*15,90); }
                        }
                    }
                    g.Restore(saved);
                }
                float diameter = 144*Math.Max(8,Math.Min(35,settings.MarkerSize))/100f;
                float offset = 144*0.04f;
                float x=settings.MarkerPosition.EndsWith("left")?offset:144-offset-diameter;
                float y=settings.MarkerPosition.StartsWith("top")?offset:144-offset-diameter;
                Color color=StateColor(state);
                if(settings.Glow>0 && state!="Offline") for(int i=8;i>=1;i--) {
                    float spread=i*0.65f;
                    using(var halo=new SolidBrush(Color.FromArgb((int)(settings.Glow*0.13f),color))) g.FillEllipse(halo,x-spread,y-spread,diameter+2*spread,diameter+2*spread);
                }
                using(var brush = new SolidBrush(color)) using(var outline = new Pen(state=="Offline"?Color.FromArgb(155,163,177):Color.FromArgb(20,22,26),2)) {
                    g.FillEllipse(brush,x,y,diameter,diameter);
                    g.DrawEllipse(outline,x,y,diameter,diameter);
                }
            }
            return bmp;
        }
        public static string DataUrl(string icon, string state, ButtonSettings settings) {
            return DataUrl(icon,state,settings,0);
        }
        public static string DataUrl(string icon, string state, ButtonSettings settings, int frame) {
            using(var bmp=Render(icon,state,settings,frame)) using(var ms=new MemoryStream()) {
                bmp.Save(ms,ImageFormat.Png); return "data:image/png;base64,"+Convert.ToBase64String(ms.ToArray());
            }
        }
    }
    public static class PluginInstaller {
        public const string FolderName = "com.openproject.tray.sdPlugin";
        static readonly string[] Required = {"manifest.json","bin/OpenProjectPlugin.exe","bin/OpenProjectTray.Shared.dll","static/OpenProject.ico","static/icon.png","static/property_inspector.html","static/inspector.js"};
        static void NoLinks(string path) {
            for (var info = new DirectoryInfo(Path.GetFullPath(path)); info != null; info = info.Parent)
                if(info.Exists && (info.Attributes & FileAttributes.ReparsePoint)!=0) throw new IOException("Папка не должна быть ссылкой: " + info.FullName);
        }
        static void CopyTree(string source, string target) {
            NoLinks(source); Directory.CreateDirectory(target);
            foreach(string file in Directory.GetFiles(source)) {
                if ((File.GetAttributes(file)&FileAttributes.ReparsePoint)!=0) throw new IOException("Unexpected linked file");
                File.Copy(file,Path.Combine(target,Path.GetFileName(file)),true);
            }
            foreach(string dir in Directory.GetDirectories(source)) CopyTree(dir,Path.Combine(target,Path.GetFileName(dir)));
        }
        static void CheckUnlocked(string path) {
            NoLinks(path);
            foreach(string file in Directory.GetFiles(path)) {
                if ((File.GetAttributes(file)&FileAttributes.ReparsePoint)!=0) throw new IOException("Unexpected linked file");
                using(var stream=new FileStream(file,FileMode.Open,FileAccess.ReadWrite,FileShare.None)) { }
            }
            foreach(string dir in Directory.GetDirectories(path)) CheckUnlocked(dir);
        }
        public static string Install(string package, string parent, string exe) {
            package = Path.GetFullPath(package); parent = Path.GetFullPath(parent);
            if(parent.TrimEnd(Path.DirectorySeparatorChar).EndsWith(".sdPlugin",StringComparison.OrdinalIgnoreCase)) throw new IOException("Выберите родительскую папку plugins, не папку .sdPlugin.");
            foreach(string file in Required) if(!File.Exists(Path.Combine(package,file))) throw new IOException("Неполный пакет плагина: " + file);
            if(!File.Exists(exe)) throw new FileNotFoundException("Сначала соберите или установите OpenProjectTray.exe",exe);
            NoLinks(parent); Directory.CreateDirectory(parent);
            string target = Path.Combine(parent,FolderName);
            if(String.Equals(package.TrimEnd('\\'),target.TrimEnd('\\'),StringComparison.OrdinalIgnoreCase) || target.StartsWith(package.TrimEnd('\\')+"\\",StringComparison.OrdinalIgnoreCase)) throw new IOException("Нельзя устанавливать плагин внутрь его исходного пакета.");
            string stage=target+".staging-"+Guid.NewGuid().ToString("N"), backup=target+".backup-"+Guid.NewGuid().ToString("N");
            bool moved = false;
            try {
                CopyTree(package,stage);
                File.WriteAllText(Path.Combine(stage,"connection.json"),new JavaScriptSerializer().Serialize(new {exePath=Path.GetFullPath(exe)}));
                if(Directory.Exists(target)) { CheckUnlocked(target); Directory.Move(target,backup); moved=true; }
                try { Directory.Move(stage,target); } catch { if(moved) Directory.Move(backup,target); throw; }
                // Settings belong to the StreamDock action contexts, outside the plugin package.
                if(moved) { try { Directory.Delete(backup,true); } catch { /* backup retained, install is valid */ } }
                return target;
            } finally { if(Directory.Exists(stage)) Directory.Delete(stage,true); }
        }
    }
}
