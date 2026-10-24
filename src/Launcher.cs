using Text=QitesXmlLoader.Text;
using System;
using System.IO;
using System.Threading;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Windows.Forms;
class Launcher {
 [STAThread] static int Main(string[] args){
  string root=Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location);
  bool pipe=args.Length>=1&&args[0]=="--pipe";
  try {
   string errorDecision="stop";
   if(pipe)for(int i=1;i<args.Length;i++){if(args[i]=="--ignore-errors"&&errorDecision=="stop")errorDecision="reject";else if(args[i]=="--approve-errors"&&errorDecision=="stop")errorDecision="approve";else throw new ArgumentException("Use --pipe with at most one of --ignore-errors or --approve-errors.");}
   string language=System.Globalization.CultureInfo.CurrentUICulture.TwoLetterISOLanguageName=="ja"?"ja":"en";
   string settings=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"QitesXmlLoader","settings.json");
   if(File.Exists(settings)){try{var values=(System.Collections.Generic.Dictionary<string,object>)new System.Web.Script.Serialization.JavaScriptSerializer().DeserializeObject(File.ReadAllText(settings));if(values.ContainsKey("Language"))language=Convert.ToString(values["Language"]);}catch{}}
   for(int n=0;n+1<args.Length;n+=2)if(args[n].Equals("-Language",StringComparison.OrdinalIgnoreCase))language=args[n+1];
   if(language!="ja"&&language!="en")language="ja";
   Text.Load(Path.Combine(root,"i18n",language+".json"));
   using(var runspace=RunspaceFactory.CreateRunspace()){
    runspace.ApartmentState=ApartmentState.STA;runspace.ThreadOptions=PSThreadOptions.UseCurrentThread;runspace.Open();
    // The setting applies only to this application process, just like Start.cmd.
    using(var policy=PowerShell.Create()){policy.Runspace=runspace;policy.AddCommand("Set-ExecutionPolicy").AddParameter("Scope","Process").AddParameter("ExecutionPolicy","Bypass").AddParameter("Force");policy.Invoke();}
    using(var ps=PowerShell.Create()){
     ps.Runspace=runspace;ps.AddCommand(Path.Combine(root,pipe?"Pipe.ps1":"QitesXmlLoader.ps1"));
     if(pipe)ps.AddParameter("ErrorDecision",errorDecision);
     if(!pipe)for(int i=0;i<args.Length;i+=2){if(i+1>=args.Length)throw new ArgumentException(Text.Get("引数に値が必要です。"));string name=args[i].TrimStart('-');if(name!="LibraryXml"&&name!="DiagnosticsPath"&&name!="CacheDirectory"&&name!="Language")throw new ArgumentException(Text.Get("未対応の引数です。"));ps.AddParameter(name,args[i+1]);}
     ps.Invoke();
     // HadErrors also records errors that the script caught and handled. In
     // that case the error stream can be empty after a successful window close.
     if(ps.InvocationStateInfo.State==PSInvocationState.Failed || ps.Streams.Error.Count>0){
      var details=new System.Text.StringBuilder();
      foreach(var error in ps.Streams.Error){details.AppendLine(error.ToString());details.AppendLine(error.ScriptStackTrace);if(error.InvocationInfo!=null)details.AppendLine(error.InvocationInfo.PositionMessage);}
      if(ps.InvocationStateInfo.Reason!=null)details.AppendLine(ps.InvocationStateInfo.Reason.ToString());
      if(details.Length==0)details.AppendLine("The application script failed without an error record.");
      throw new Exception(details.ToString());
     }
    }
   }return 0;
  }catch(Exception e){if(pipe){Console.Error.WriteLine(new System.Web.Script.Serialization.JavaScriptSerializer().Serialize(new{type="fatal",message=e.ToString()}));return 1;}string log=Path.Combine(Path.GetTempPath(),"QitesXmlLoader-launch-error.txt");File.WriteAllText(log,e.ToString());MessageBox.Show(e.Message+"\n"+log,Text.Get("Qites xml loader 起動エラー"));return 1;}
 }
}
