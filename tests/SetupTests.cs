using System;
using System.IO;
using System.Reflection;
using System.Collections.Generic;
static class TestFolders {
    public static string Root;
    public static string GetFolderPath(Environment.SpecialFolder folder) {
        string path=Path.Combine(Root,folder.ToString()); Directory.CreateDirectory(path); return path;
    }
}
sealed class FakeKey : IDisposable {
    readonly Dictionary<string,object> values=new Dictionary<string,object>();
    public void SetValue(string key,object value){values[key]=value;}
    public object GetValue(string key){return GetValue(key,null);}
    public object GetValue(string key,object fallback){object value;return values.TryGetValue(key,out value)?value:fallback;}
    public void Dispose(){}
}
sealed class FakeRegistryRoot {
    readonly Dictionary<string,FakeKey> keys=new Dictionary<string,FakeKey>();
    public FakeKey OpenSubKey(string path){FakeKey value;return keys.TryGetValue(path,out value)?value:null;}
    public FakeKey CreateSubKey(string path){var value=OpenSubKey(path);if(value==null){value=new FakeKey();keys[path]=value;}return value;}
    public void DeleteSubKeyTree(string path,bool missing){keys.Remove(path);}
}
static class FakeRegistry { public static readonly FakeRegistryRoot CurrentUser=new FakeRegistryRoot(); }
class SetupTests {
    static void Set(string key,object value){typeof(Setup).GetField(key,BindingFlags.Static|BindingFlags.NonPublic).SetValue(null,value);}
    static void Call(string method,string path){try{typeof(Setup).GetMethod(method,BindingFlags.Static|BindingFlags.NonPublic).Invoke(null,new object[]{path});}catch(TargetInvocationException e){throw e.InnerException;}}
    static void Check(bool ok,string message){if(!ok)throw new Exception(message);Console.WriteLine("PASS "+message);}
    static int Main(string[] args){
        try{
            TestFolders.Root=Path.Combine(args[0],"build/obj/setup-test-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(TestFolders.Root);
            Set("silent",true);
            string old=Path.Combine(TestFolders.Root,"old-settings.json");File.WriteAllText(old,"{\"OpenProjectRoot\":\"/custom/project\"}");Set("importSettings",old);
            string destination=Path.Combine(TestFolders.Root,"Приложение с пробелами");
            Call("Install",destination);
            Check(File.ReadAllText(Path.Combine(destination,"settings.json"))==File.ReadAllText(old),"installer imports old settings");
            Check(File.Exists(Path.Combine(destination,"OpenProjectTray.exe")),"installer deploys app");
            Check(File.Exists(Path.Combine(TestFolders.GetFolderPath(Environment.SpecialFolder.Programs),"OpenProject Tray.lnk")),"installer creates shortcut");
            string settings=Path.Combine(destination,"settings.json");File.WriteAllText(settings,"{\"Url\":\"http://localhost:3999\"}");
            Directory.CreateDirectory(Path.Combine(destination,"logs"));File.WriteAllText(Path.Combine(destination,"logs/user.log"),"keep");
            File.WriteAllText(Path.Combine(destination,"personal.txt"),"keep");
            Call("Install",destination);
            Check(File.ReadAllText(settings).Contains("3999"),"update preserves current settings");
            Check(File.ReadAllText(Path.Combine(destination,"logs/user.log"))=="keep","update preserves logs");
            bool locked=false;
            using(var file=new FileStream(Path.Combine(destination,"OpenProjectTray.Shared.dll"),FileMode.Open,FileAccess.Read,FileShare.None)){
                try{Call("Install",destination);}catch(IOException){locked=true;}
            }
            Check(locked && File.Exists(settings),"locked update leaves app data intact");
            Check(!File.ReadAllText(Path.Combine(destination,"installed-files.txt")).Contains("personal.txt"),"uninstall manifest excludes personal files");
            Call("Uninstall",destination);
            Check(!File.Exists(Path.Combine(destination,"OpenProjectTray.exe")),"uninstall removes binaries");
            Check(File.Exists(settings)&&File.Exists(Path.Combine(destination,"logs/user.log"))&&File.Exists(Path.Combine(destination,"personal.txt")),"uninstall preserves settings logs and personal files");
            Console.WriteLine("PASS installer suite uses fake registry and sandboxed shortcuts");return 0;
        }catch(Exception e){Console.Error.WriteLine(e);return 1;}
    }
}
