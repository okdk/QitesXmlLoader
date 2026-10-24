using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Windows.Forms;
class Setup {
 [STAThread]static int Main(string[] args){
  bool quiet=false;string receipt=null,target=null;
  for(int i=0;i<args.Length;i++){
   if(args[i]=="--quiet")quiet=true;
   else if(args[i]=="--receipt"&&i+1<args.Length)receipt=args[++i];
   else if(args[i]=="--target"&&i+1<args.Length)target=args[++i];
   else return 2;
  }
  try{
   string root=Path.Combine(Path.GetTempPath(),"QitesXmlLoader-setup-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(root);
   string zip=Path.Combine(root,"payload.zip");
   using(var input=Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip"))using(var output=new FileStream(zip,FileMode.CreateNew)){input.CopyTo(output);}
   ZipFile.ExtractToDirectory(zip,root);
   string arguments="-NoProfile -ExecutionPolicy Bypass -File "+Quote(Path.Combine(root,"Install.ps1"));
   if(receipt!=null)arguments+=" -ReceiptPath "+Quote(receipt);
   if(target!=null)arguments+=" -InstallDirectory "+Quote(target);
   var start=new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),@"WindowsPowerShell\v1.0\powershell.exe"),arguments){UseShellExecute=false,CreateNoWindow=quiet};
   using(var process=Process.Start(start)){process.WaitForExit();if(process.ExitCode!=0)throw new Exception("Installation failed: "+process.ExitCode);}
   if(!quiet)MessageBox.Show(System.Globalization.CultureInfo.CurrentUICulture.TwoLetterISOLanguageName=="ja"?"インストールしました。スタートメニューから起動できます。FFmpegは別途インストールしてパスを指定してください。":"Installed. Launch from the Start menu. Install FFmpeg separately and set its path in the app.","Qites xml loader");return 0;
  }catch(Exception error){File.WriteAllText(Path.Combine(Path.GetTempPath(),"QitesXmlLoader-setup-error.txt"),error.ToString());if(!quiet)MessageBox.Show(error.Message,"Qites xml loader");return 1;}
 }
 static string Quote(string value){if(value.IndexOf('"')>=0)throw new ArgumentException("A path cannot contain quotes.");return "\""+value.TrimEnd('\\')+"\"";}
}
