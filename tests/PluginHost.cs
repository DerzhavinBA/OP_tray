using System;
using System.Threading;
using OpenProjectTray;
class PluginHost {
    static int Main() {
        using(var server=new BridgeServer()) {
            server.Publish("Stopped",false,"","");
            var drain=new Thread(()=>{
                while(true) { if(server.TakeActivation()) { server.Publish("Starting",true,"test",""); Console.WriteLine("activate"); } Thread.Sleep(20); }
            });
            drain.IsBackground=true; drain.Start();
            Console.WriteLine("ready");
            string line;
            while((line=Console.ReadLine())!=null) {
                if(line=="exit") return 0;
                server.Publish(line=="ErrorBusy"?"Error":line,line=="Starting"||line=="ErrorBusy","",line=="ErrorBusy"?"mock error":"");
                Console.WriteLine("published:"+line);
            }
        }
        return 0;
    }
}
