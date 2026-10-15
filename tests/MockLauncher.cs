using System;
using System.IO;
using System.Threading;
using OpenProjectTray;
class MockLauncher {
    static void Main(string[] args) {
        string folder=AppDomain.CurrentDomain.BaseDirectory;
        File.WriteAllText(Path.Combine(folder,"launched"),String.Join(" ",args));
        using(var server=new BridgeServer()) {
            while(!File.Exists(Path.Combine(folder,"exit-launcher"))) {
                if(server.TakeActivation()) File.AppendAllText(Path.Combine(folder,"launch-activations"),"activate\n");
                server.Publish("Stopped",false,"","");Thread.Sleep(50);
            }
        }
    }
}
