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
