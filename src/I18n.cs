using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
using System.Globalization;
using System.Web.Script.Serialization;
namespace QitesXmlLoader {
 public static class Text {
  static Dictionary<string,object> strings=new Dictionary<string,object>();
  public static string Culture="ja";
  public static bool Loaded;
  public static void Load(string path){var catalog=(Dictionary<string,object>)new JavaScriptSerializer{MaxJsonLength=Int32.MaxValue}.DeserializeObject(File.ReadAllText(path,Encoding.UTF8));strings=(Dictionary<string,object>)catalog["Strings"];Culture=(string)catalog["Culture"];Loaded=true;}
  public static string Get(string key,params object[] values){object translated;string value=strings.TryGetValue(key,out translated)?Convert.ToString(translated):key;return values!=null&&values.Length>0?String.Format(CultureInfo.GetCultureInfo(Culture),value,values):value;}
 }
}
