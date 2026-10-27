import {cp,mkdir,readdir,lstat,writeFile,readFile} from 'node:fs/promises';
import path from 'node:path';
const root=process.cwd(), outputs=path.resolve(root,'../../outputs');
const version=(await readFile(path.join(root,'pubspec.yaml'),'utf8')).match(/^version:\s*([0-9.]+)/m)[1];
const app=path.join(outputs,`Relay-Windows-${version}`), source=path.join(outputs,`Relay-Flutter-source-${version}`);
await mkdir(app,{recursive:true});await mkdir(source,{recursive:true});
const release=path.join(root,'build/windows/x64/runner/Release');
for(const entry of await readdir(release)){
  if(entry==='relay_native.exe'||entry.endsWith('.pdb'))continue;
  await cp(path.join(release,entry),path.join(app,entry),{recursive:true});
}
// App-local Visual C++ runtime distribution, from the installed official toolchain.
const crt='C:/Program Files/Microsoft Visual Studio/18/Community/VC/Redist/MSVC/14.51.36231/x64/Microsoft.VC145.CRT';
for(const name of await readdir(crt))if(name.endsWith('.dll'))await cp(path.join(crt,name),path.join(app,name));
const excluded=new Set(['build','.dart_tool','ephemeral','.gradle','Pods','.symlinks','xcuserdata','.git']);
async function filter(file){if(excluded.has(path.basename(file))||path.basename(file)==='local.properties'||file.endsWith('.log')||file.endsWith('.iml'))return false;return !(await lstat(file)).isSymbolicLink();}
for(const name of ['lib','test','integration_test','android','ios','macos','windows','examples','tool','pubspec.yaml','pubspec.lock','analysis_options.yaml','README.md','.gitignore','.metadata'])await cp(path.join(root,name),path.join(source,name),{recursive:true,filter});
const guide=await readFile(path.join(root,'README.md'),'utf8');
await writeFile(path.join(outputs,`Relay-Flutter-guide-${version}.md`),guide);
await writeFile(path.join(app,'Relay-guide.md'),guide);
await writeFile(path.join(app,'READ-ME.txt'),'Relay — Windows x64\r\n\r\nفك ضغط المجلد كاملاً ثم افتح Relay.exe. لا تنقل EXE وحده.\r\nExtract the whole folder, then open Relay.exe. Keep DLL files and data beside it.\r\n\r\nالإعدادات: أدخل رقم واتساب المعتمد وAccount SID ومفتاح API وسره، ثم احفظ واختبر الاتصال.\r\nSettings: enter your approved WhatsApp sender, Account SID and API key/secret, then Save & test connection.\r\n\r\nهذا تطبيق فعلي، والإرسال يستخدم رصيد Twilio. ابدأ بجهة واحدة تملكها ووافقت على التواصل.\r\nThis is the native app. Sending uses your Twilio balance. Start with one consenting recipient you control.\r\n\r\nSee Relay-guide.md for full Arabic/English instructions.\r\n');
console.log('Prepared Windows app and portable Flutter source.');
