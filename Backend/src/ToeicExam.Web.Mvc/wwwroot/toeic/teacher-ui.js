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
