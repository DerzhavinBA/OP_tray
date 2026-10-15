using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Text;
using System.Windows.Forms;
using System.Web.Script.Serialization;
using Microsoft.Win32;

class Setup {
    const string Product = "OpenProjectTray";
    const string RegistryPath = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\OpenProjectTray";
    static bool silent;
    static string importSettings = "";
    static string FindOldSettings() {
        string linkPath=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Startup),"OpenProject Tray.lnk");
        if(File.Exists(linkPath)) {
            var type=Type.GetTypeFromProgID("WScript.Shell"); dynamic shell=Activator.CreateInstance(type);
            dynamic link=shell.CreateShortcut(linkPath);
            string folder=Convert.ToString(link.WorkingDirectory);
            if(String.IsNullOrEmpty(folder)) folder=Path.GetDirectoryName(Convert.ToString(link.TargetPath));
            System.Runtime.InteropServices.Marshal.FinalReleaseComObject(link); System.Runtime.InteropServices.Marshal.FinalReleaseComObject(shell);
            if(!String.IsNullOrEmpty(folder) && File.Exists(Path.Combine(folder,"settings.json"))) return Path.Combine(folder,"settings.json");
        }
        string adjacent=Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"../settings.json"));
        return File.Exists(adjacent) ? adjacent : "";
    }
    static void CheckPath(string path) {
        for(var d=new DirectoryInfo(path);d!=null;d=d.Parent)
            if(d.Exists && (d.Attributes&FileAttributes.ReparsePoint)!=0) throw new IOException("Папка не должна быть ссылкой: "+d.FullName);
    }
    static string Child(string root,string relative) {
        string full=Path.GetFullPath(Path.Combine(root,relative));
        if(!full.StartsWith(root.TrimEnd('\\')+"\\",StringComparison.OrdinalIgnoreCase)) throw new IOException("Invalid package path");
        return full;
    }
    static void Extract(string directory) {
        directory=Path.GetFullPath(directory); CheckPath(directory); Directory.CreateDirectory(directory);
        using(var stream=Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip")) {
            if(stream==null) throw new IOException("Installation payload is missing");
            using(var zip=new ZipArchive(stream,ZipArchiveMode.Read)) foreach(var entry in zip.Entries) {
                string file=Child(directory,entry.FullName.Replace('/','\\'));
                if(entry.Name.Length==0) { Directory.CreateDirectory(file); continue; }
                Directory.CreateDirectory(Path.GetDirectoryName(file));
                using(var input=entry.Open()) using(var output=File.Create(file)) input.CopyTo(output);
            }
        }
    }
    static void Shortcut(string file,string exe,string arguments) {
        Directory.CreateDirectory(Path.GetDirectoryName(file));
        var type=Type.GetTypeFromProgID("WScript.Shell"); dynamic shell=Activator.CreateInstance(type);
        dynamic link=shell.CreateShortcut(file); link.TargetPath=exe; link.Arguments=arguments;
        link.WorkingDirectory=Path.GetDirectoryName(exe); link.IconLocation=exe+",0"; link.Save();
        System.Runtime.InteropServices.Marshal.FinalReleaseComObject(link);
        System.Runtime.InteropServices.Marshal.FinalReleaseComObject(shell);
    }
    static void Install(string destination) {
        destination=Path.GetFullPath(destination); CheckPath(destination);
        string imported = null;
        string settingsTarget=Path.Combine(destination,"settings.json");
        if(!File.Exists(settingsTarget) && !String.IsNullOrWhiteSpace(importSettings)) {
            imported=File.ReadAllText(importSettings);
            if(new JavaScriptSerializer().DeserializeObject(imported) as Dictionary<string,object> == null) throw new IOException("Файл настроек должен содержать JSON-объект.");
        }
        string stage=Path.Combine(Path.GetTempPath(),Product+"-"+Guid.NewGuid().ToString("N"));
        string backup=Path.Combine(stage,"backup");
        var written=new List<string>(); var originals=new List<string>();
        try {
            string payload=Path.Combine(stage,"payload"); Extract(payload);
            var files=Directory.GetFiles(payload,"*",SearchOption.AllDirectories);
            // Check every destination before changing the installation.
            foreach(string source in files) {
                string relative=source.Substring(payload.Length+1), target=Child(destination,relative);
                CheckPath(Path.GetDirectoryName(target));
                if(File.Exists(target)) {
                    if((File.GetAttributes(target)&FileAttributes.ReparsePoint)!=0) throw new IOException("Linked installation file");
                    using(var check=new FileStream(target,FileMode.Open,FileAccess.ReadWrite,FileShare.None)) { }
                }
            }
            try {
                foreach(string source in files) {
                    string relative=source.Substring(payload.Length+1), target=Child(destination,relative);
                    Directory.CreateDirectory(Path.GetDirectoryName(target));
                    if(File.Exists(target)) {
                        string old=Child(backup,relative); Directory.CreateDirectory(Path.GetDirectoryName(old));
                        File.Copy(target,old); originals.Add(relative);
                    }
                    written.Add(relative); File.Copy(source,target,true);
                }
            } catch {
                foreach(string relative in written) {
                    string target=Child(destination,relative);
                    if(originals.Contains(relative)) File.Copy(Child(backup,relative),target,true); else if(File.Exists(target)) File.Delete(target);
                }
                throw;
            }
            if(imported!=null) File.WriteAllText(settingsTarget,imported, new UTF8Encoding(false));
            string exe=Path.Combine(destination,"OpenProjectTray.exe");
            Shortcut(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs),"OpenProject Tray.lnk"),exe,"");
            Shortcut(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),"OpenProject Tray.lnk"),exe,"");
            string startup=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Startup),"OpenProject Tray.lnk");
            if(File.Exists(startup)) Shortcut(startup,exe,"--background --startup");
            using(var key=Registry.CurrentUser.CreateSubKey(RegistryPath)) {
                key.SetValue("DisplayName","OpenProject Tray"); key.SetValue("DisplayVersion","1.1.0");
                key.SetValue("Publisher","OpenProject Tray"); key.SetValue("InstallLocation",destination);
                key.SetValue("DisplayIcon",exe); key.SetValue("UninstallString","\""+Path.Combine(destination,"Uninstall.exe")+"\" /uninstall");
                key.SetValue("NoModify",1); key.SetValue("NoRepair",1);
            }
            if(!silent) MessageBox.Show("OpenProject Tray установлен.\nЗапустите ярлык приложения. Плагин устанавливается через меню трея «Плагин StreamDock…».","OpenProject Tray");
        } finally { if(Directory.Exists(stage)) Directory.Delete(stage,true); }
    }
    static void Uninstall(string root) {
        root=Path.GetFullPath(root); CheckPath(root);
        using(var key=Registry.CurrentUser.OpenSubKey(RegistryPath)) {
            if(key==null || !String.Equals(Convert.ToString(key.GetValue("InstallLocation")),root,StringComparison.OrdinalIgnoreCase)) throw new IOException("Папка не совпадает с установленным приложением.");
        }
        string manifest=Path.Combine(root,"installed-files.txt");
        if(!File.Exists(manifest)) throw new IOException("Отсутствует список файлов установки.");
        var files=new List<string>();
        foreach(string relative in File.ReadAllLines(manifest)) {
            if(String.IsNullOrWhiteSpace(relative)) continue;
            string file=Child(root,relative); CheckPath(Path.GetDirectoryName(file));
            if(File.Exists(file)) { using(var check=new FileStream(file,FileMode.Open,FileAccess.ReadWrite,FileShare.None)) { } files.Add(file); }
        }
        foreach(string file in files) File.Delete(file);
        foreach(var folder in new [] {Environment.SpecialFolder.Programs,Environment.SpecialFolder.DesktopDirectory,Environment.SpecialFolder.Startup}) {
            string shortcut=Path.Combine(Environment.GetFolderPath(folder),"OpenProject Tray.lnk"); if(File.Exists(shortcut)) File.Delete(shortcut);
        }
        Registry.CurrentUser.DeleteSubKeyTree(RegistryPath,false);
        if(!silent) MessageBox.Show("Приложение удалено. Настройки, журналы, плагин StreamDock и OpenProject сохранены.","OpenProject Tray");
    }
    [STAThread] static int Main(string[] args) {
        silent=Array.Exists(args,a=>a.Equals("/S",StringComparison.OrdinalIgnoreCase));
        try {
            int remove=Array.IndexOf(args,"--remove");
            if(remove>=0) { Uninstall(args[remove+1]); return 0; }
#if UNINSTALL
            if(!silent && MessageBox.Show("Удалить OpenProject Tray? Перед удалением закройте трей. OpenProject и база данных сохранятся.","OpenProject Tray",MessageBoxButtons.YesNo)!=DialogResult.Yes) return 0;
            string temporary=Path.Combine(Path.GetTempPath(),Product+"-Uninstall-"+Guid.NewGuid().ToString("N")+".exe");
            File.Copy(Assembly.GetExecutingAssembly().Location,temporary);
            var process=new ProcessStartInfo(temporary,"--remove \""+AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\')+"\""+(silent?" /S":""));
            process.UseShellExecute=false; process.CreateNoWindow=true; process.WindowStyle=ProcessWindowStyle.Hidden;
            Process.Start(process); return 0;
#else
            int extract=Array.IndexOf(args,"--extract");
            if(extract>=0) { Extract(args[extract+1]); return 0; }
            string destination=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Programs",Product);
            importSettings=FindOldSettings();
            using(var key=Registry.CurrentUser.OpenSubKey(RegistryPath)) if(key!=null) destination=Convert.ToString(key.GetValue("InstallLocation",destination));
            foreach(string arg in args) if(arg.StartsWith("/DIR=",StringComparison.OrdinalIgnoreCase)) destination=arg.Substring(5);
            foreach(string arg in args) if(arg.StartsWith("/IMPORT=",StringComparison.OrdinalIgnoreCase)) importSettings=arg.Substring(8);
            if(!silent) {
                Application.EnableVisualStyles();
                using(var dialog=new Form()) {
                    dialog.Text="Установка OpenProject Tray"; dialog.ClientSize=new System.Drawing.Size(580,240); dialog.StartPosition=FormStartPosition.CenterScreen;
                    dialog.FormBorderStyle=FormBorderStyle.FixedDialog; dialog.MaximizeBox=false;
                    var label=new Label {Text="Папка установки (перед обновлением закройте трей):",Left=16,Top=16,Width=545};
                    var path=new TextBox {Text=destination,Left=16,Top=48,Width=450};
                    var browse=new Button {Text="Обзор…",Left=475,Top=46,Width=88};
                    browse.Click+=(s,e)=>{using(var picker=new FolderBrowserDialog()){picker.SelectedPath=path.Text;if(picker.ShowDialog()==DialogResult.OK)path.Text=picker.SelectedPath;}};
                    var importLabel=new Label {Text="Старый settings.json (необязательно; существующие настройки сохраняются):",Left=16,Top=88,Width=545,Height=32};
                    var importBox=new TextBox {Text=importSettings,Left=16,Top=124,Width=450};
                    var importBrowse=new Button {Text="Обзор…",Left=475,Top=122,Width=88};
                    importBrowse.Click+=(s,e)=>{using(var picker=new OpenFileDialog()){picker.Filter="Настройки JSON|*.json";if(picker.ShowDialog()==DialogResult.OK)importBox.Text=picker.FileName;}};
                    var install=new Button {Text="Установить",Left=420,Top=185,Width=140};
                    install.Click+=(s,e)=>{ install.Enabled=false; try {importSettings=importBox.Text.Trim();Install(path.Text);dialog.DialogResult=DialogResult.OK;dialog.Close();} catch(Exception ex){MessageBox.Show(ex.Message+"\nЗакройте трей и повторите установку.","Ошибка",MessageBoxButtons.OK,MessageBoxIcon.Error);} finally {install.Enabled=true;} };
                    dialog.Controls.AddRange(new Control[]{label,path,browse,importLabel,importBox,importBrowse,install}); return dialog.ShowDialog()==DialogResult.OK?0:1;
                }
            }
            Install(destination); return 0;
#endif
        } catch(Exception e) { if(!silent) MessageBox.Show(e.Message,"OpenProject Tray",MessageBoxButtons.OK,MessageBoxIcon.Error); return 1; }
    }
}
