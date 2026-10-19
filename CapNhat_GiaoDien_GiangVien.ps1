param([string]$ProjectRoot = $PSScriptRoot)
$ErrorActionPreference = 'Stop'
$web = Join-Path $ProjectRoot 'Backend\src\ToeicExam.Web.Mvc\wwwroot\toeic'
$index = Join-Path $web 'index.html'
if (!(Test-Path -LiteralPath $index)) { throw "Không thấy $index. Đặt script trong thư mục kiemtragk hoặc truyền -ProjectRoot." }
$html = [IO.File]::ReadAllText($index)
foreach ($required in @('showExamStatistics','id="workspace"','id="sessionForm"','id="examJson"','word-import.js')) {
    if (!$html.Contains($required)) { throw "Thiếu thành phần $required. Chưa thay đổi file. Cần bản giao diện TOEIC và bản bổ sung thống kê đã cài." }
}
if ([regex]::Matches($html,'(?i)</head>').Count -ne 1 -or [regex]::Matches($html,'(?i)</body>').Count -ne 1) { throw 'Cấu trúc index.html không phù hợp. Chưa thay đổi file.' }
$css = @'
/* Local stylesheet: works without Tailwind CDN, remote fonts or images. */
:root{--ink:#0b1c30;--muted:#64748b;--blue:#2563eb;--deep:#004ac6;--line:#e1e8f3;--canvas:#f5f7fc;--teal:#006a63}
body.faculty-ui{font-family:'Be Vietnam Pro','Segoe UI',Arial,sans-serif;font-size:14px;color:var(--ink);background:var(--canvas);line-height:1.6}
.faculty-ui [hidden]{display:none!important}.faculty-ui svg{width:22px;height:22px;flex-shrink:0}.faculty-ui h1{font-size:30px;letter-spacing:-.8px;line-height:1.3;margin:6px 0 10px}.faculty-ui h2{font-size:20px;letter-spacing:-.4px;margin:0 0 14px}.faculty-ui h3{font-size:16px}.faculty-ui p{line-height:1.7}.faculty-ui .hint{color:var(--muted);font-size:13px}.faculty-ui small{opacity:1;color:var(--muted);font-size:12px}.faculty-ui .eyebrow{font-size:11px;font-weight:700;letter-spacing:1.6px;margin:0 0 12px}
.faculty-ui button,.faculty-ui .linkButton{font:600 13px 'Segoe UI',sans-serif;border:1px solid var(--blue);border-radius:8px;background:var(--blue);color:white;min-height:42px;padding:10px 16px;cursor:pointer;transition:background .16s,box-shadow .16s;text-decoration:none;display:inline-flex;align-items:center;justify-content:center;gap:9px}
.faculty-ui button:hover{background:#1d4ed8;box-shadow:0 3px 10px #2563eb20}.faculty-ui button:disabled{opacity:.5;cursor:wait;box-shadow:none}.faculty-ui button.secondary{background:#fff;color:var(--deep);border-color:#cddaf3}.faculty-ui button.secondary:hover{background:#eff4ff}.faculty-ui button:focus-visible,.faculty-ui a:focus-visible,.faculty-ui summary:focus-visible{outline:3px solid #80d5cb;outline-offset:3px}
.faculty-ui input,.faculty-ui select,.faculty-ui textarea{font:14px 'Segoe UI',sans-serif;border:1px solid #d3ddec;background:#fff;color:var(--ink);border-radius:8px;padding:12px;max-width:100%;width:100%;min-height:44px}.faculty-ui input:focus,.faculty-ui select:focus,.faculty-ui textarea:focus{outline:2px solid #b4c5ff;border-color:var(--blue)}.faculty-ui input[type=checkbox]{width:17px;min-height:17px;height:17px;accent-color:var(--blue)}.faculty-ui label{font-size:13px;font-weight:600;margin:14px 0 7px}.faculty-ui section{border:1px solid var(--line);background:#fff;border-radius:13px;padding:26px;margin:0 0 22px;box-shadow:0 3px 14px #17356a03}.faculty-ui .actions{display:flex;gap:10px;flex-wrap:wrap;margin:18px 0}.faculty-ui .pill{display:inline-block;background:#edf3ff;color:#194ca8;padding:5px 10px;border-radius:6px;font-size:12px;margin:4px 8px 4px 0}
.faculty-ui>main{max-width:none;margin:0;padding:36px}.faculty-ui>.facultyTopbar{height:76px;background:white;border-bottom:1px solid var(--line);color:var(--ink);padding:0 36px;gap:22px}.facultyTopbar strong{font-size:17px}.facultyTopbar small{font-size:11px;margin:0}.faculty-ui .topDate{margin-left:auto;font-size:12px;color:var(--muted)}.faculty-ui .facultyNav{display:none}.faculty-ui #message:empty{display:none}.faculty-ui #message{border:1px solid #f3cca1;background:#fff7e8;color:#8a4909;padding:14px 18px;border-radius:10px;margin-bottom:22px;white-space:pre-wrap;overflow-wrap:anywhere}.faculty-ui #message.success{background:#e9f8f3;color:#065f46;border-color:#bde5d5}.faculty-ui .menuToggle{display:none}
.facultyAuthenticated>main{margin-left:248px;padding-top:108px}.facultyAuthenticated>.facultyTopbar{position:fixed;left:248px;right:0;top:0;z-index:30}.facultyAuthenticated .facultyNav{display:flex;flex-direction:column;position:fixed;inset:0 auto 0 0;width:248px;background:white;border-right:1px solid var(--line);padding:28px 18px 18px;z-index:40}.facultyLogo{display:flex;align-items:center;gap:12px;font-size:22px;font-weight:750;letter-spacing:-.7px;color:var(--deep);padding:0 12px 24px}.facultyLogo svg{width:31px;height:31px}.navCaption{font-size:10px;letter-spacing:1.4px;color:#8b98ac;font-weight:700;padding:0 13px;margin:12px 0}.faculty-ui .navButton{border:0;background:transparent;color:#58677e;width:100%;justify-content:flex-start;padding:13px;margin:3px 0;font-weight:500}.faculty-ui .navButton:hover{background:#eff4ff;box-shadow:none}.faculty-ui .navButton.active{background:var(--blue);color:#fff;box-shadow:0 4px 12px #2563eb25}.navFoot{border-top:1px solid var(--line);margin-top:auto;padding:20px 12px 0;display:flex;flex-direction:column;overflow-wrap:anywhere}.navFoot .eyebrow{color:#8b98ac;margin-bottom:6px}.navFoot strong{font-size:14px}.facultyPageTitle{margin-bottom:28px}.facultyPageTitle .eyebrow{color:var(--teal);margin:0}.facultyPageTitle .hint{margin:0}
.faculty-ui .facultyLoginShell{display:grid;grid-template-columns:44% 56%;max-width:1040px;min-height:600px;margin:28px auto;background:#fff;border-radius:20px;overflow:hidden;box-shadow:0 18px 65px #1e3a6815;border:1px solid var(--line)}.faculty-ui #login{max-width:none;margin:0;padding:64px 50px;border:0;border-radius:0;align-self:center;box-shadow:none}.faculty-ui #login h1{font-size:27px}.faculty-ui #login .hint{margin:10px 0 28px}.faculty-ui #loginForm>.actions button{width:100%;min-height:48px}.loginIntro{background:radial-gradient(circle at 0 0,#5887ed55,transparent 50%),linear-gradient(140deg,#1556ca,#072d7c);padding:52px 40px;color:#fff;display:flex;flex-direction:column;position:relative}.loginIntro>svg{margin-top:45px;width:50px;height:50px;color:#9cf2e8}.loginIntro h2{font-size:32px;line-height:1.4;white-space:pre-line;margin-top:28px;letter-spacing:-1px}.loginIntro p{color:#d9e5ff;font-size:14px}.loginIntro small{margin-top:auto;color:#c4d6ff;padding-top:40px}.loginChips{display:flex;flex-wrap:wrap;gap:8px;margin-top:25px}.loginChips span{border:1px solid #ffffff35;border-radius:6px;padding:7px 10px;font-size:11px;background:#ffffff0b}.passwordWrap{position:relative}.faculty-ui .passwordWrap input{padding-right:70px}.faculty-ui .passwordToggle{position:absolute;right:5px;top:5px;min-height:34px;padding:6px 10px;background:transparent;border:0;color:var(--muted)}
.faculty-ui .dashboardHero{display:flex;justify-content:space-between;align-items:center;gap:24px;background:linear-gradient(115deg,#e8efff,#f0fbf9);border-color:#dbe7f8;padding:28px 32px}.dashboardHero h2{font-size:25px;margin-bottom:6px}.dashboardHero p{margin:0;color:#516481}.dashboardHero .eyebrow{color:var(--teal);margin-bottom:10px}.dashboardHero .actions{flex-shrink:0}.metricGrid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:18px;margin-bottom:25px}.metricCard{background:#fff;border:1px solid var(--line);border-radius:12px;padding:22px;position:relative;display:flex;flex-direction:column}.metricCard svg{color:var(--blue);margin-bottom:16px}.metricCard>span{font-size:12px;font-weight:600;color:#64748b}.metricCard strong{font-size:34px;margin:5px 0;letter-spacing:-1px}.metricCard small{font-size:11px}.dashboardSession{display:flex;align-items:center;justify-content:space-between;gap:20px;border-top:1px solid var(--line);padding:18px 0}.dashboardSession p{margin:3px 0}.dashboardSession>div:last-child{display:flex;gap:10px;align-items:center}.quickGuide{background:#eff4ff!important}.quickGuide p{margin-bottom:0}.emptyState{padding:25px 0;color:var(--muted)}
.bankToolbar{display:grid;grid-template-columns:minmax(180px,1fr) 190px auto auto;gap:12px;align-items:center}.faculty-ui #exams{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:18px}.faculty-ui #exams>.card{border:1px solid var(--line);border-radius:10px;padding:22px;margin:0;background:#fff}.faculty-ui #exams>.card>strong{display:block;font-size:16px;line-height:1.55;margin-bottom:10px}.faculty-ui #exams>.card>.hint{margin-bottom:16px}.faculty-ui #exams button{margin:3px 5px 3px 0;font-size:12px;min-height:36px;padding:8px 12px}.faculty-ui #sessions>.card{border:1px solid var(--line);border-radius:10px;margin:14px 0;padding:22px}.faculty-ui #sessions button{margin:5px}.faculty-ui #sessionForm>.row{gap:32px}.faculty-ui #users{max-height:260px;overflow:auto;border:1px solid var(--line);padding:12px;border-radius:8px}.faculty-ui #users label{display:flex;align-items:center;gap:9px;margin:8px 0;font-weight:400}
.importSteps{display:grid;grid-template-columns:repeat(3,1fr);gap:12px;margin:20px 0 24px}.importSteps span{background:#eef4ff;color:#2356b3;border-radius:8px;padding:13px;font-size:12px;font-weight:600}.faculty-ui .uploadPanel{border:2px dashed #b7cbf4;background:#f7faff;padding:26px;border-radius:12px}.faculty-ui .uploadPanel>strong{display:block;font-size:17px}.faculty-ui input[type=file]{background:#fff;padding:16px}.faculty-ui input::file-selector-button{border:0;border-radius:6px;padding:9px 12px;background:#e7efff;color:#164dbb;font-weight:600;margin-right:12px;cursor:pointer}.faculty-ui details{margin:20px 0}.faculty-ui summary{cursor:pointer;font-weight:600;color:#2458bc;padding:8px 0}.faculty-ui .advancedEditor{border:1px solid var(--line);border-radius:9px;padding:12px 18px}.faculty-ui textarea{min-height:270px;font-family:Consolas,monospace;font-size:12px}.faculty-ui pre{white-space:pre-wrap;overflow-wrap:anywhere;font:13px/1.7 Consolas,monospace;max-width:100%}.faculty-ui #preview .card{box-shadow:none;margin:15px 0}.faculty-ui #preview img{max-width:100%;height:auto}.faculty-ui table{width:100%;border-collapse:collapse}.faculty-ui th{background:#f4f7fc;color:#64748b;font-size:11px;text-transform:uppercase;letter-spacing:.5px;white-space:nowrap}.faculty-ui td,.faculty-ui th{padding:13px 12px;border-bottom:1px solid var(--line);text-align:left}.faculty-ui td{font-size:13px}.resultPicker{display:flex;gap:12px;margin:15px 0}.resultPicker select{flex:1}.resultPicker button{flex-shrink:0}.studentRow{display:flex;align-items:center;gap:14px;padding:15px 0;border-bottom:1px solid var(--line)}.studentRow .hint{margin-left:auto}.avatar{display:inline-flex;width:38px;height:38px;align-items:center;justify-content:center;border-radius:50%;background:#e7efff;color:var(--deep);font-weight:700}.studentList{margin-top:20px}.faculty-ui #reportSection,.faculty-ui #examStatisticsSection{overflow:auto}
@media(min-width:1700px){.facultyAuthenticated>main{padding-left:60px;padding-right:60px}}
@media(max-width:1200px){.metricGrid{grid-template-columns:repeat(2,minmax(0,1fr))}.bankToolbar{grid-template-columns:1fr 1fr}.dashboardHero{flex-direction:column;align-items:flex-start!important}.faculty-ui #exams{grid-template-columns:1fr}.faculty-ui .facultyLoginShell{max-width:950px}}
@media(max-width:850px){.facultyAuthenticated>main{margin-left:0;padding:95px 18px 25px}.facultyAuthenticated>.facultyTopbar{left:0;padding:0 18px;gap:15px}.facultyAuthenticated .facultyNav{transform:translateX(-100%);transition:transform .2s}.facultyAuthenticated.navOpen .facultyNav{transform:translateX(0);box-shadow:10px 0 60px #0b1c3030}.faculty-ui .menuToggle{display:inline-flex;padding:4px 10px;min-height:35px}.faculty-ui .topDate{display:none}.facultyTopbar #logout{margin-left:auto}.faculty-ui>main{padding:20px}.faculty-ui .facultyLoginShell{grid-template-columns:1fr;max-width:530px;margin:15px auto}.loginIntro{padding:25px 30px}.loginIntro>svg,.loginIntro p,.loginIntro small,.loginChips{display:none}.loginIntro h2{font-size:22px;white-space:normal;margin:8px 0}.faculty-ui #login{padding:30px}.faculty-ui .row{grid-template-columns:1fr}.dashboardSession{align-items:flex-start;flex-direction:column}}
@media(max-width:480px){.faculty-ui h1{font-size:25px}.faculty-ui section{padding:18px}.metricGrid{gap:10px}.metricCard{padding:16px}.metricCard strong{font-size:28px}.importSteps{grid-template-columns:1fr;gap:6px}.bankToolbar{grid-template-columns:1fr}.resultPicker{flex-direction:column}.faculty-ui .dashboardHero{padding:22px}.studentRow{flex-wrap:wrap}.studentRow .hint{margin-left:0}.faculty-ui .facultyTopbar strong{font-size:14px}}

'@
$js = @'
/* TOEIC lecturer UI, adapted from the four supplied Stitch screens.
   Existing forms, IDs, listeners and API authorization are preserved. */
(() => {
  'use strict';
  if (document.getElementById('facultyNav')) return;
  const byId = id => document.getElementById(id);
  if (!byId('workspace') || !byId('sessionForm') || !byId('examJson')) return;
  const el = (tag, value, cls) => { const x=document.createElement(tag); if(value!=null)x.textContent=value; if(cls)x.className=cls; return x; };
  const button = (label, action, cls='secondary') => { const b=el('button',label,cls); b.type='button'; b.onclick=action; return b; };
  const icon = name => {
    const paths={book:'M4 4h6a3 3 0 0 1 3 3v14a4 4 0 0 0-4-2H4z M20 4h-4a3 3 0 0 0-3 3v14a4 4 0 0 1 4-2h3z',grid:'M3 3h7v7H3z M14 3h7v7h-7z M3 14h7v7H3z M14 14h7v7h-7z',calendar:'M4 5h16v16H4z M8 2v6 M16 2v6 M4 11h16',chart:'M4 3v18h17 M8 16v-5 M13 16V7 M18 16V3',upload:'M12 16V3 M7 8l5-5 5 5 M4 16v5h16v-5',people:'M16 21v-3a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v3 M9 10a4 4 0 1 0 0-8 4 4 0 0 0 0 8 M20 21v-3a4 4 0 0 0-3-4 M17 3a4 4 0 0 1 0 8'};
    const s=document.createElementNS('http://www.w3.org/2000/svg','svg'); s.setAttribute('viewBox','0 0 24 24');s.setAttribute('fill','none');s.setAttribute('stroke','currentColor');s.setAttribute('stroke-width','1.7');s.setAttribute('aria-hidden','true');
    const p=document.createElementNS(s.namespaceURI,'path');p.setAttribute('d',paths[name]||paths.book);s.append(p);return s;
  };
  const workspace=byId('workspace'), main=document.querySelector('body > main');
  document.body.classList.add('faculty-ui');
  const legacyHeader=document.querySelector('body > header');
  legacyHeader.classList.add('facultyTopbar');
  const brand=legacyHeader.firstElementChild;brand.replaceChildren(el('strong','TOEIC CLASSROOM'),el('small','Cổng quản lý giảng viên'));
  const prep=byId('examJson').closest('section'), bank=byId('exams').closest('section'), setup=byId('sessionForm').closest('section'), sessions=byId('sessions').closest('section'), reportSection=byId('reportSection');
  const pageLabels={overview:'Tổng quan',exams:'Ngân hàng đề thi',import:'Nhập đề từ Word',sessions:'Ca thi & lịch thi',results:'Kết quả & thống kê',students:'Sinh viên'};
  const pages={};
  for(const key of Object.keys(pageLabels)){const p=el('div',null,'facultyPage');p.dataset.page=key;p.hidden=true;pages[key]=p;}
  // Move existing nodes, never clone forms or replace their event handlers.
  pages.import.append(prep);pages.exams.append(bank);pages.sessions.append(setup,sessions);pages.results.append(reportSection);
  workspace.replaceChildren(...Object.values(pages));
  const title=el('div',null,'facultyPageTitle');const kicker=el('p','TOEIC READING · GIẢNG VIÊN','eyebrow');const titleText=el('h1','Tổng quan');const subtitle=el('p','Quản lý đề thi, lịch thi và kết quả học tập.','hint');title.append(kicker,titleText,subtitle);workspace.prepend(title);
  const nav=el('aside',null,'facultyNav');nav.id='facultyNav';
  const logo=el('div',null,'facultyLogo');logo.append(icon('book'),el('div','TOEIC Portal'));nav.append(logo,el('p','PHÂN HỆ GIẢNG DẠY','navCaption'));
  const links=el('nav');nav.append(links);
  const navDefs=[['overview','Tổng quan','grid'],['exams','Đề thi TOEIC','book'],['sessions','Ca thi & lịch thi','calendar'],['students','Sinh viên','people'],['results','Kết quả & thống kê','chart'],['import','Nhập đề Word','upload']];
  const navButtons={};let current='overview';
  for(const [key,label,shape] of navDefs){const b=button(label,()=>navigate(key),'navButton');b.prepend(icon(shape));navButtons[key]=b;links.append(b);}
  const navFoot=el('div',null,'navFoot');const identity=el('strong','Giảng viên');navFoot.append(el('span','TÀI KHOẢN','eyebrow'),identity,el('small','Quản lý TOEIC Reading'));nav.append(navFoot);document.body.prepend(nav);
  const menu=button('☰',()=>document.body.classList.toggle('navOpen'),'menuToggle');menu.setAttribute('aria-label','Mở hoặc đóng thanh điều hướng');legacyHeader.prepend(menu);
  const dateLabel=el('span',new Intl.DateTimeFormat('vi-VN',{dateStyle:'long'}).format(new Date()),'topDate');legacyHeader.insertBefore(dateLabel,byId('logout'));
  function navigate(key){
    if(!pages[key])return;current=key;
    for(const [k,p] of Object.entries(pages))p.hidden=k!==key;
    for(const [k,b] of Object.entries(navButtons)){b.classList.toggle('active',k===key);if(k===key)b.setAttribute('aria-current','page');else b.removeAttribute('aria-current');}
    titleText.textContent=pageLabels[key];document.body.classList.remove('navOpen');
    subtitle.textContent=key==='import'?'Đọc file có thẻ, kiểm tra cấu trúc và rà soát bản nháp trước khi xuất bản.':key==='exams'?'Reading 100 câu · 75 phút · Part 5: 30 / Part 6: 16 / Part 7: 54.':'Dữ liệu từ các đề và ca thi do bạn quản lý.';
    window.scrollTo({top:0,behavior:'smooth'});
  }
  // Login: keep the original authentication form and permission checks.
  const login=byId('login');const loginShell=el('div',null,'facultyLoginShell');login.before(loginShell);
  const intro=el('div',null,'loginIntro');intro.append(el('div','TOEIC CLASSROOM','eyebrow'),icon('book'),el('h2','Một nơi quản lý.\nMỗi kỳ thi rõ ràng.'),el('p','Chuẩn bị đề Reading, điều phối ca thi và theo dõi kết quả sinh viên trên cùng một hệ thống.'));
  const chips=el('div',null,'loginChips');['100 câu Reading','75 phút làm bài','Part 5 · 6 · 7'].forEach(s=>chips.append(el('span',s)));intro.append(chips,el('small','Không gian làm việc dành cho giảng viên.'));
  loginShell.append(intro,login);login.querySelector('h1').textContent='Cổng thông tin giảng viên';
  login.querySelector('.hint').textContent='Đăng nhập bằng tài khoản giảng viên được cấp quyền quản lý TOEIC.';
  const password=byId('password');const pwWrap=el('div',null,'passwordWrap');password.before(pwWrap);pwWrap.append(password,button('Hiện',e=>{const visible=password.type==='password';password.type=visible?'text':'password';e.currentTarget.textContent=visible?'Ẩn':'Hiện';},'passwordToggle'));
  byId('username').placeholder='Tên đăng nhập';password.placeholder='Nhập mật khẩu';
  function authState(){const active=!workspace.classList.contains('hidden');document.body.classList.toggle('facultyAuthenticated',active);loginShell.hidden=active;if(active){identity.textContent=byId('username').value.trim()||'Giảng viên';navigate(current);}}
  new MutationObserver(authState).observe(workspace,{attributes:true,attributeFilter:['class']});authState();
  // Import screen: actual importer controls and exact tag convention.
  prep.querySelector('h2').textContent='Nhập đề thi TOEIC Reading';
  prep.querySelector(':scope > .hint').textContent='File .docx có thẻ, tối đa 40.000.000 byte. Chỉ tạo bản nháp khi nội dung hợp lệ. Đáp án được khai báo bằng thẻ [ANSWER] A/B/C/D.';
  const steps=el('div',null,'importSteps');['01 · Chọn Word','02 · Kiểm tra nội dung','03 · Rà soát & xuất bản'].forEach(s=>steps.append(el('span',s)));prep.querySelector('h2').after(steps);
  const file=prep.querySelector('input[type=file]');if(file){const panel=file.parentElement;panel.classList.add('uploadPanel');file.addEventListener('change',()=>{if(file.files[0])file.dataset.selected=file.files[0].name;});}
  const editor=el('details',null,'advancedEditor');editor.append(el('summary','Chỉnh nội dung bản nháp / JSON nâng cao'));
  const sampleActions=byId('sample').parentElement;const jsonLabel=Array.from(prep.children).find(n=>n.tagName==='LABEL');
  if(jsonLabel)editor.append(jsonLabel);editor.append(byId('examJson'),byId('createExam').parentElement,sampleActions);prep.append(editor);
  const previewDetails=byId('preview').closest('details');previewDetails.classList.add('examPreview');prep.append(previewDetails);
  new MutationObserver(()=>{if(byId('createExam').textContent.includes('phiên bản'))editor.open=true;}).observe(byId('createExam'),{childList:true,subtree:true});
  const rawTell=tell;
  tell=function(message){rawTell(message);const m=byId('message');m.classList.toggle('hasMessage',!!message);m.classList.toggle('success',/^(Đã |DOCX hợp lệ)/.test(message||''));};
  // Real counts cached from the existing requests; no fabricated dashboard figures.
  const cache={exams:[],sessions:[],users:[]};let fresh={exams:false,sessions:false,users:false};
  const rawApi=api;
  api=async function(path,...args){const data=await rawApi(path,...args);const kind=Object.keys(cache).find(k=>path==='/api/toeic/teacher/'+k && (!args[0]||args[0]==='GET'));if(kind&&Array.isArray(data)){cache[kind]=data;fresh[kind]=true;renderDashboard();if(kind==='users')renderStudents();if(kind==='exams')renderResultsPicker();}return data;};
  const dash=el('div');pages.overview.append(dash);
  function renderDashboard(){
    dash.replaceChildren();const hero=el('section',null,'dashboardHero');const greeting=el('div');greeting.append(el('p','KHÔNG GIAN GIẢNG DẠY','eyebrow'),el('h2','Sẵn sàng cho ca thi tiếp theo'),el('p','Chuẩn bị đề, mở lịch thi và theo dõi bài nộp từ một nơi.'));
    const actions=el('div',null,'actions');actions.append(button('＋ Tạo ca thi',()=>navigate('sessions'),''),button('↑ Nhập đề Word',()=>navigate('import'),'secondary'));hero.append(greeting,actions);dash.append(hero);
    const cards=el('div',null,'metricGrid');const today=new Date().toLocaleDateString('vi-VN');
    const submitted=cache.sessions.reduce((n,s)=>n+Number(s.submittedAttempts||0),0);
    const weighted=cache.sessions.reduce((n,s)=>n+Number(s.averageCorrect||0)*Number(s.submittedAttempts||0),0);
    const metrics=[['Đề đã xuất bản',fresh.exams?cache.exams.filter(e=>e.status==='Published').length:'—','Phiên bản có thể gán vào ca thi','book'],['Ca thi hôm nay',fresh.sessions?cache.sessions.filter(s=>new Date(s.startsAt).toLocaleDateString('vi-VN')===today).length:'—','Theo ngày bắt đầu ca thi','calendar'],['Bài thi đã nộp',fresh.sessions?submitted:'—','Tổng các ca do bạn quản lý','chart'],['Số câu đúng trung bình',fresh.sessions&&submitted?(weighted/submitted).toLocaleString('vi-VN',{maximumFractionDigits:2}):'—','Trên thang 100 câu Reading','grid']];
    metrics.forEach(([label,value,note,shape])=>{const card=el('article',null,'metricCard');card.append(icon(shape),el('span',label),el('strong',value),el('small',note));cards.append(card);});dash.append(cards);
    const section=el('section');section.append(el('h2','Lịch thi gần đây'));const list=el('div',null,'dashboardSessions');
    [...cache.sessions].sort((a,b)=>new Date(b.startsAt)-new Date(a.startsAt)).slice(0,5).forEach(s=>{const item=el('div',null,'dashboardSession');const info=el('div');info.append(el('strong',s.name),el('p',s.title,'hint'),el('small',`${date(s.startsAt)} → ${date(s.endsAt)}`));const right=el('div');right.append(el('span',`${s.submittedAttempts||0}/${s.candidateCount||0} đã nộp`,'pill'),button('Xem kết quả',()=>run(()=>report(s.id))));item.append(info,right);list.append(item);});
    if(!cache.sessions.length)list.append(el('p',fresh.sessions?'Chưa có ca thi. Hãy tạo ca đầu tiên.':'Chưa tải dữ liệu ca thi.','emptyState'));
    section.append(list);dash.append(section);
    const guide=el('section',null,'quickGuide');guide.append(el('h2','Quy trình tạo kỳ thi'),el('p','Nhập Word → rà soát bản nháp → xuất bản đề → tạo ca và gán sinh viên → công bố kết quả.'));dash.append(guide);
  }
  // Bank search/status filters operate on the existing cards and preserve action buttons.
  bank.querySelector('h2').textContent='Ngân hàng đề thi TOEIC Reading';const toolbar=el('div',null,'bankToolbar');
  const search=el('input');search.type='search';search.placeholder='Tìm tên đề hoặc mã phiên bản…';search.setAttribute('aria-label','Tìm đề thi');
  const status=el('select');status.setAttribute('aria-label','Lọc trạng thái');[['','Tất cả trạng thái'],['Published','Đã xuất bản'],['Draft','Bản nháp'],['Archived','Lưu trữ']].forEach(([v,t])=>{const o=el('option',t);o.value=v;status.append(o);});
  toolbar.append(search,status,byId('refresh'),button('＋ Nhập Word',()=>navigate('import'),''));byId('exams').before(toolbar);
  const bankCount=el('p','','hint');toolbar.after(bankCount);
  function filterBank(){const all=Array.from(byId('exams').querySelectorAll(':scope > .card'));let count=0;for(const card of all){const meta=card.querySelector('.hint')?.textContent||'';const matches=card.textContent.toLocaleLowerCase('vi').includes(search.value.toLocaleLowerCase('vi'))&&(!status.value||meta.includes('· '+status.value));card.hidden=!matches;if(matches)count++;}bankCount.textContent=`Hiển thị ${count}/${all.length} phiên bản đề thi`;}
  search.oninput=filterBank;status.onchange=filterBank;
  new MutationObserver(filterBank).observe(byId('exams'),{childList:true,subtree:true});
  setup.querySelector('h2').textContent='Tạo ca thi';sessions.querySelector('h2').textContent='Lịch thi đã tạo';
  setup.querySelector(':scope > .hint').textContent='Chọn đề đã xuất bản, ca sáng/chiều/tối và sinh viên được dự thi. Giờ nhập theo giờ địa phương của máy.';
  // Results: choose an exam or a session before fetching its actual report.
  const resultPicker=el('section');resultPicker.append(el('h2','Tra cứu kết quả'));const pickerRow=el('div',null,'resultPicker');const examSelect=el('select');examSelect.setAttribute('aria-label','Chọn đề thống kê');
  pickerRow.append(examSelect,button('Thống kê theo đề',()=>run(async()=>{if(!examSelect.value)throw Error('Chưa có đề để thống kê.');await showExamStatistics(Number(examSelect.value),examSelect.selectedOptions[0].textContent);}),''));resultPicker.append(pickerRow,button('Xem kết quả theo ca',()=>navigate('sessions')));pages.results.prepend(resultPicker);
  function renderResultsPicker(){const selected=examSelect.value;examSelect.replaceChildren();const seen=new Set();cache.exams.forEach(e=>{if(seen.has(e.examId))return;seen.add(e.examId);const o=el('option',`${e.title} · Đề #${e.examId}`);o.value=e.examId;examSelect.append(o);});if([...examSelect.options].some(o=>o.value===selected))examSelect.value=selected;}
  const rawReport=report;report=async function(id){navigate('results');await rawReport(id);};
  if(typeof showExamStatistics==='function'){const oldStats=showExamStatistics;showExamStatistics=async function(...args){navigate('results');await oldStats(...args);};}
  // Draft actions are attached by word-import.js. Reveal the editor before they run.
  byId('exams').addEventListener('click',e=>{const b=e.target.closest('button');if(b?.textContent.includes('sửa bản nháp')){navigate('import');editor.open=true;}},true);
  const studentsSection=el('section');pages.students.append(studentsSection);
  function renderStudents(){studentsSection.replaceChildren(el('h2','Tài khoản sinh viên'));const link=el('a','Mở trang quản lý tài khoản');link.href='/Users';link.target='_blank';link.rel='noopener';link.className='linkButton';studentsSection.append(link,el('p','Chọn sinh viên được dự thi trong mục Ca thi & lịch thi.','hint'));const list=el('div',null,'studentList');cache.users.forEach(u=>{const item=el('div',null,'studentRow');item.append(el('span',(u.name||u.userName||'?').slice(0,1).toUpperCase(),'avatar'),el('strong',`${u.surname||''} ${u.name||''}`.trim()||u.userName),el('span',u.userName,'hint'));list.append(item);});if(!cache.users.length)list.append(el('p',fresh.users?'Chưa có tài khoản sinh viên.':'Chưa tải danh sách sinh viên.'));studentsSection.append(list);}
  // Re-open the import view after save/import calls load(), preserving all existing data.
  const oldLoad=load;load=async function(...args){await oldLoad(...args);filterBank();};
  renderDashboard();renderStudents();filterBank();navigate('overview');
})();

'@
if (!$html.Contains('teacher-ui.css')) { $html = [regex]::Replace($html,'(?i)</head>','<link rel="stylesheet" href="./teacher-ui.css?v=1" />' + "`r`n</head>") }
if (!$html.Contains('teacher-ui.js')) { $html = [regex]::Replace($html,'(?i)</body>','<script src="./teacher-ui.js?v=1"></script>' + "`r`n</body>") }
$backup = Join-Path $ProjectRoot ('Backup_GiaoDien_GV_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
New-Item -ItemType Directory -Path $backup | Out-Null
foreach ($name in @('index.html','teacher-ui.css','teacher-ui.js')) {
    $p = Join-Path $web $name
    if (Test-Path -LiteralPath $p) { Copy-Item -LiteralPath $p -Destination (Join-Path $backup $name) }
}
$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $web 'teacher-ui.css'),$css,$utf8)
[IO.File]::WriteAllText((Join-Path $web 'teacher-ui.js'),$js,$utf8)
[IO.File]::WriteAllText($index,$html,$utf8)
Write-Host 'ĐÃ CÀI GIAO DIỆN GIẢNG VIÊN.' -ForegroundColor Green
Write-Host "Bản sao lưu: $backup"
Write-Host 'Mở http://localhost:5000/toeic/index.html và nhấn Ctrl + F5.'
Write-Host 'Không cần chạy lại SQL. Script chỉ cập nhật 3 file giao diện.'
