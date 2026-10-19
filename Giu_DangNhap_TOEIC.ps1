param([string]$ProjectRoot = $PSScriptRoot)
$ErrorActionPreference='Stop'
$utf8=New-Object System.Text.UTF8Encoding($false)
$updates=@{}
function Read-Source([string]$relative) {
 $p=Join-Path $ProjectRoot $relative
 if (!(Test-Path -LiteralPath $p)) { throw "Không thấy file: $p" }
 return [IO.File]::ReadAllText($p).Replace("`r`n","`n")
}
$updates['lib/toeic/toeic_api.dart']=Read-Source 'lib/toeic/toeic_api.dart'
$updates['lib/toeic/student_mobile_app.dart']=Read-Source 'lib/toeic/student_mobile_app.dart'
if ($updates['lib/toeic/toeic_api.dart'].Contains('TOEIC_SESSION_RESTORE_V1')) { Write-Host 'Bản giữ đăng nhập đã được cài.'; exit 0 }
$old=@'
import 'dart:convert';
'@
$new=@'
import 'dart:convert';
import 'session_storage_stub.dart'
    if (dart.library.js_interop) 'session_storage_web.dart' as session;
'@
if ([regex]::Matches($updates['lib/toeic/toeic_api.dart'],[regex]::Escape($old)).Count -ne 1) { throw 'Code hiện tại khác bản đã kiểm tra. Chưa ghi thay đổi; gửi lại file lib/toeic/toeic_api.dart.' }
$updates['lib/toeic/toeic_api.dart']=$updates['lib/toeic/toeic_api.dart'].Replace($old,$new)
$old=@'
  void logout() {
'@
$new=@'
  // TOEIC_SESSION_RESTORE_V1
  String get _sessionKey => 'toeic.student.session.v1:$baseUrl';
  Future<bool> restoreSession() async {
    final saved = session.readSession(_sessionKey);
    if (saved == null || saved.isEmpty) return false;
    _token = saved;
    _profile = Map<String, dynamic>.from(await request('/api/toeic/me') as Map);
    return true;
  }

  void logout() {
    session.clearSession(_sessionKey);
'@
if ([regex]::Matches($updates['lib/toeic/toeic_api.dart'],[regex]::Escape($old)).Count -ne 1) { throw 'Code hiện tại khác bản đã kiểm tra. Chưa ghi thay đổi; gửi lại file lib/toeic/toeic_api.dart.' }
$updates['lib/toeic/toeic_api.dart']=$updates['lib/toeic/toeic_api.dart'].Replace($old,$new)
$old=@'
    dynamic value;
'@
$new=@'
    if (response.statusCode == 401) {
      logout();
      throw Exception('Phiên đăng nhập hết hạn. Vui lòng đăng nhập lại.');
    }
    dynamic value;
'@
if ([regex]::Matches($updates['lib/toeic/toeic_api.dart'],[regex]::Escape($old)).Count -ne 1) { throw 'Code hiện tại khác bản đã kiểm tra. Chưa ghi thay đổi; gửi lại file lib/toeic/toeic_api.dart.' }
$updates['lib/toeic/toeic_api.dart']=$updates['lib/toeic/toeic_api.dart'].Replace($old,$new)
$old=@'
        await request('/api/toeic/me') as Map,
      );
'@
$new=@'
        await request('/api/toeic/me') as Map,
      );
      session.writeSession(_sessionKey, _token!);
'@
if ([regex]::Matches($updates['lib/toeic/toeic_api.dart'],[regex]::Escape($old)).Count -ne 1) { throw 'Code hiện tại khác bản đã kiểm tra. Chưa ghi thay đổi; gửi lại file lib/toeic/toeic_api.dart.' }
$updates['lib/toeic/toeic_api.dart']=$updates['lib/toeic/toeic_api.dart'].Replace($old,$new)
$old=@'
    _api = widget.api ?? ToeicApi();
'@
$new=@'
    _api = widget.api ?? ToeicApi();
    Future.microtask(_restoreSession);
'@
if ([regex]::Matches($updates['lib/toeic/student_mobile_app.dart'],[regex]::Escape($old)).Count -ne 1) { throw 'Code hiện tại khác bản đã kiểm tra. Chưa ghi thay đổi; gửi lại file lib/toeic/student_mobile_app.dart.' }
$updates['lib/toeic/student_mobile_app.dart']=$updates['lib/toeic/student_mobile_app.dart'].Replace($old,$new)
$old=@'
  Future<void> _login() async {
'@
$new=@'
  Future<void> _restoreSession() async {
    setState(() => _busy = true);
    try {
      final restored = await _api.restoreSession();
      if (!mounted || !restored) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => _StudentHome(api: _api)),
      );
      _api.logout();
    } catch (error) {
      if (mounted) setState(() => _message = _error(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _login() async {
'@
if ([regex]::Matches($updates['lib/toeic/student_mobile_app.dart'],[regex]::Escape($old)).Count -ne 1) { throw 'Code hiện tại khác bản đã kiểm tra. Chưa ghi thay đổi; gửi lại file lib/toeic/student_mobile_app.dart.' }
$updates['lib/toeic/student_mobile_app.dart']=$updates['lib/toeic/student_mobile_app.dart'].Replace($old,$new)
$updates['Backend/src/ToeicExam.Web.Mvc/wwwroot/toeic/session-keep.js']=@'
// Session persistence for the lecturer portal.
(() => {
 const key='toeic.teacher.session.v1';
 const read=()=>{try{return JSON.parse(sessionStorage.getItem(key)||'null')}catch{return null}};
 const clear=()=>sessionStorage.removeItem(key);
 const oldApi=api;
 api=async function(path,...args){
   const value=await oldApi(path,...args);
   if(path==='/api/toeic/me' && value.canManage && token){
     sessionStorage.setItem(key,JSON.stringify({token,user:document.getElementById('username').value}));
   }
   return value;
 };
 const logout=document.getElementById('logout');
 logout.addEventListener('click',clear,true);
 const stored=read();if(!stored?.token)return;
 token=stored.token;document.getElementById('username').value=stored.user||'';
 const submit=document.querySelector('#loginForm button');if(submit)submit.disabled=true;
 (async()=>{
   try{
     const r=await fetch('/api/toeic/me',{headers:{Authorization:'Bearer '+token},credentials:'omit'});
     if(r.status===401||r.status===403){clear();token=null;throw Error('Phiên đăng nhập hết hạn hoặc không còn quyền truy cập. Vui lòng đăng nhập lại.');}
     if(!r.ok)throw Error('Chưa khôi phục được phiên (HTTP '+r.status+'). Phiên vẫn được giữ; nhấn F5 để thử lại.');
     const raw=await r.json();const me=raw.__abp?raw.result:raw;
     if(!me.canManage){clear();token=null;throw Error('Tài khoản không có quyền quản lý TOEIC.');}
     document.getElementById('login').classList.add('hidden');
     document.getElementById('workspace').classList.remove('hidden');
     logout.classList.remove('hidden');await load();
   }catch(e){tell(e.message||String(e));}finally{if(submit)submit.disabled=false;}
 })();
})();

'@
$updates['lib/toeic/session_storage_stub.dart']=@'
String? readSession(String key) => null;
void writeSession(String key, String value) {}
void clearSession(String key) {}

'@
$updates['lib/toeic/session_storage_web.dart']=@'
import 'dart:js_interop';
@JS('window.sessionStorage.getItem')
external JSString? _getItem(JSString key);
@JS('window.sessionStorage.setItem')
external void _setItem(JSString key, JSString value);
@JS('window.sessionStorage.removeItem')
external void _removeItem(JSString key);
String? readSession(String key) => _getItem(key.toJS)?.toDart;
void writeSession(String key, String value) => _setItem(key.toJS, value.toJS);
void clearSession(String key) => _removeItem(key.toJS);

'@
$html=Read-Source 'Backend/src/ToeicExam.Web.Mvc/wwwroot/toeic/index.html'
if (!$html.Contains('teacher-ui.js')) { throw 'Chưa thấy bản giao diện giảng viên mới. Chưa ghi thay đổi.' }
if (!$html.Contains('session-keep.js')) { $html=$html.Replace('</body>', '<script src="./session-keep.js?v=1"></script></body>') }
$updates['Backend/src/ToeicExam.Web.Mvc/wwwroot/toeic/index.html']=$html
$backup=Join-Path $ProjectRoot ('Backup_GiuDangNhap_'+(Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
foreach($relative in $updates.Keys){
 $p=Join-Path $ProjectRoot $relative
 if(Test-Path -LiteralPath $p){
  $b=Join-Path $backup $relative
  New-Item -ItemType Directory -Force -Path (Split-Path $b) | Out-Null
  Copy-Item -LiteralPath $p -Destination $b
 }
}
foreach($relative in $updates.Keys){ [IO.File]::WriteAllText((Join-Path $ProjectRoot $relative),$updates[$relative],$utf8) }
Write-Host 'Đã cài giữ đăng nhập khi F5 cho giảng viên và Flutter trên Chrome.' -ForegroundColor Green
Write-Host "Sao lưu: $backup"
Write-Host 'Khởi động lại Flutter. Trang giảng viên nhấn Ctrl+F5. Đăng nhập lại một lần để lưu phiên.'
