'use strict';
const $ = id => document.getElementById(id);
const screens = ['homeScreen','setupScreen','gameScreen','handoffScreen','singleResultScreen','multiResultScreen'];
let gameId = null, mode = 'single', difficulty = 'easy', state = null;
let selectedTower = null, paused = false, startedAt = 0, elapsedBeforePause = 0, timerHandle = null;
let currentName = 'Player', isDragging = false;

function showScreen(id) {
  screens.forEach(s => $(s).classList.toggle('active', s === id));
  $('pauseOverlay').classList.add('hidden');
  window.scrollTo({top:0, behavior:'smooth'});
}
function errorText(err) {
  const messages = {empty_source:'That tower is empty.', same_tower:'Choose a different tower.', larger_on_smaller:'A larger disk cannot go on a smaller disk.', game_not_active:'This game is not accepting moves.', undo_unavailable:'There is no move to undo.'};
  return messages[err] || String(err || 'Something went wrong.');
}
async function api(path, method='GET', body=null) {
  const options = {method, headers:{}};
  if (body) { options.headers['Content-Type']='application/json'; options.body=JSON.stringify(body); }
  const response = await fetch('/api/'+path+(method==='GET' && body?.id ? '?id='+encodeURIComponent(body.id) : ''), options);
  if (!response.ok) throw new Error('Server returned '+response.status);
  return response.json();
}
function showSetup(nextMode) {
  mode = nextMode;
  $('setupEyebrow').textContent = mode === 'single' ? 'YOUR SOLO ADVENTURE' : 'A LITTLE FRIENDLY COMPETITION';
  $('setupTitle').textContent = mode === 'single' ? 'Let’s get started!' : 'Gather your players!';
  $('singleFields').classList.toggle('hidden', mode !== 'single');
  $('multiFields').classList.toggle('hidden', mode !== 'multi');
  if (mode === 'multi') renderNameInputs();
  $('setupError').textContent = '';
  showScreen('setupScreen');
}
function renderNameInputs() {
  const count = Number($('playerCount').value);
  const box = $('playerNames'); box.innerHTML = '';
  for (let i=0;i<count;i++) {
    const wrap=document.createElement('div'), label=document.createElement('label'), input=document.createElement('input');
    label.textContent='Player '+(i+1)+' name'; input.maxLength=24; input.placeholder='Player '+(i+1); input.value='Player '+(i+1); input.id='playerName'+i;
    wrap.append(label,input); box.append(wrap);
  }
}
function selectedDifficulty() { return difficulty; }
function formatTime(seconds) {
  const s=Math.max(0,Math.floor(seconds)), m=Math.floor(s/60);
  return String(m).padStart(2,'0')+':'+String(s%60).padStart(2,'0');
}
function elapsed() { return elapsedBeforePause + (paused ? 0 : (Date.now()-startedAt)/1000); }
function startTimer(reset=true) {
  if (timerHandle) clearInterval(timerHandle);
  if (reset) elapsedBeforePause=0;
  startedAt=Date.now(); paused=false;
  timerHandle=setInterval(()=>$('timerValue').textContent=formatTime(elapsed()),250);
  $('timerValue').textContent=formatTime(elapsed());
}
function stopTimer() { if(timerHandle) clearInterval(timerHandle); timerHandle=null; }
function pauseTimer() { if(paused)return; elapsedBeforePause=elapsed(); paused=true; stopTimer(); }
function renderBoard() {
  if (!state) return;
  const towers=state.towers || [[],[],[]], names=['a','b','c'];
  names.forEach((name,i)=>{
    const stack=$('stack-'+name); stack.innerHTML='';
    (towers[i] || []).slice().reverse().forEach(disk=>{
      const el=document.createElement('div'); el.className='disk'; el.dataset.disk=disk;
      const n=Number(state.disks||3), width= Math.max(27, 34 + (disk/n)*58);
      el.style.width=width+'%'; el.style.background=['','#ffb4d1','#f58db8','#e96fa5','#d95691','#c94482'][disk] || '#dc6b9e';
      stack.append(el);
    });
    const tower=document.querySelector('.tower[data-tower="'+name+'"]');
    tower.classList.toggle('selected',selectedTower===name);
    tower.classList.toggle('valid-target',selectedTower && selectedTower!==name);
  });
  $('movesValue').textContent=state.moves;
  $('parValue').textContent=state.par;
  $('statusValue').textContent=state.status==='solved'?'Solved':'Playing';
  $('playerLine').textContent=(mode==='single'?'Playing as '+currentName:'Current turn: '+(state.current_player||''));
  $('boardHint').textContent=selectedTower?'Now choose a destination tower.':'Click a tower, then choose where to place its top disk.';
}
function setFeedback(text, good=false) { $('feedback').textContent=text; $('feedback').style.color=good?'#3c9a70':'#a35d7e'; }
async function refreshFrom(response) {
  if (!response.valid) { setFeedback(errorText(response.error)); return false; }
  state=response; renderBoard(); return true;
}
async function move(from,to) {
  if (!gameId || paused || !state || state.status!=='playing' || (mode==='multi' && state.phase!=='playing')) return;
  try {
    const result=await api('move','POST',{id:gameId,from,to});
    if (!result.valid) { playEffect('error'); setFeedback(errorText(result.error)); selectedTower=null; renderBoard(); return; }
    await refreshFrom(result); selectedTower=null; playEffect('move'); setFeedback('Lovely move! ✦',true);
    if (result.finished || result.status==='solved') {
      playEffect('victory'); stopTimer(); const seconds=Math.round(elapsed());
      const finish=await api('finish','POST',{id:gameId,time:seconds});
      if (mode==='single') showSingleResult(finish);
      else if (finish.phase==='handoff') showHandoff();
      else if (finish.phase==='results') await showMultiResults();
    }
  } catch(e) { setFeedback('Cannot reach the Prolog server. Is it running?'); }
}
function chooseTower(name) {
  if (!state || paused || state.status!=='playing') return;
  if (!selectedTower) { playEffect('select'); selectedTower=name; renderBoard(); setFeedback('Tower '+name.toUpperCase()+' selected. Pick a destination.'); return; }
  if (selectedTower===name) { selectedTower=null; renderBoard(); setFeedback('Selection cleared.'); return; }
  const from=selectedTower; move(from,name);
}
function renderGameStart(data) {
  state=data; selectedTower=null; $('gameModeLabel').textContent=mode==='single'?'SINGLE PLAYER':'MULTIPLAYER · '+data.disks+' DISKS';
  $('difficultyLabel').textContent=difficulty.toUpperCase()+' · '+data.disks+' DISKS';
  $('singleControls').classList.toggle('hidden',mode!=='single');
  $('undoBtn').disabled=false; $('restartBtn').disabled=false;
  $('timerValue').textContent='00:00'; startTimer(true); renderBoard(); setFeedback('Choose a tower to begin ♡');
  showScreen('gameScreen');
}
async function createGame() {
  try {
    let payload={mode,difficulty:selectedDifficulty()};
    if(mode==='single') { currentName=$('singleName').value.trim()||'Player'; payload.name=currentName; }
    else {
      payload.names=Array.from({length:Number($('playerCount').value)},(_,i)=>$('playerName'+i).value.trim()||'Player '+(i+1));
      payload.basis=$('basis').value;
    }
    const data=await api('new','POST',payload);
    if(!data.valid) throw new Error(data.error||'Could not create game');
    gameId=data.id; renderGameStart(data);
  } catch(e) { $('setupError').textContent='Could not start the game. Check that SWI-Prolog is running.'; }
}
function showSingleResult(data) {
  $('winnerName').textContent=currentName;
  $('resultMoves').textContent=data.moves;
  $('resultTime').textContent=formatTime(data.completion_time||elapsedBeforePause);
  $('resultPar').textContent=data.par;
  const stars=Number(data.stars||1); $('starRating').textContent='★'.repeat(stars)+'☆'.repeat(3-stars);
  $('starCaption').textContent=stars===3?'Perfect par — absolutely flawless!':stars===2?'Wonderful work — so close to par!':'Puzzle complete — you did it!';
  showScreen('singleResultScreen'); celebrate();
}
function showHandoff() {
  stopTimer(); const next=state.current_player || 'the next player';
  $('nextPlayerName').textContent=next; showScreen('handoffScreen');
}
async function readyNext() {
  try { const data=await api('ready','POST',{id:gameId}); if(!data.valid)throw new Error(data.error); renderGameStart(data); }
  catch(e){alert('Could not start the next turn. Please try again.');}
}
async function showMultiResults() {
  try {
    const data=await api('results','GET',{id:gameId});
    if(!data.valid)throw new Error(data.error);
    $('multiWinnerNames').textContent=data.winners.join(', ')+(data.winners.length>1?' — it’s a tie!':' takes the crown!');
    $('multiWinnerTitle').textContent=data.winners.length>1?'A sparkling tie!':'The crown goes to…';
    const body=$('rankingRows'); body.innerHTML='';
    data.ranking.forEach((p,i)=>{
      const tr=document.createElement('tr'); if(data.winners.includes(p.name))tr.className='winner-row';
      [p.rank,p.name,p.moves,formatTime(p.time),data.winners.includes(p.name)?'Winner ♛':'Completed'].forEach(v=>{const td=document.createElement('td');td.textContent=v;tr.append(td);});
      body.append(tr);
    });
    showScreen('multiResultScreen'); celebrate();
  } catch(e) { setFeedback('Results are not available yet.'); }
}
function celebrate() {
  const area=$('celebration'); area.classList.remove('hidden'); area.innerHTML='';
  for(let i=0;i<36;i++){const p=document.createElement('span');p.className='petal';p.textContent=['✿','❀','♥','✧'][i%4];p.style.left=Math.random()*100+'%';p.style.animationDuration=(3+Math.random()*4)+'s';p.style.animationDelay=Math.random()*2+'s';area.append(p);}
  for(let i=0;i<6;i++){const f=document.createElement('i');f.className='firework';f.style.left=(10+Math.random()*80)+'%';f.style.top=(8+Math.random()*55)+'%';f.style.animationDelay=Math.random()+'s';area.append(f);}
  for(let i=0;i<5;i++){const l=document.createElement('span');l.className='lantern';l.textContent='🏮';l.style.left=(8+i*20)+'%';l.style.animationDelay=(i*.7)+'s';area.append(l);}
  setTimeout(()=>area.classList.add('hidden'),8500);
}
async function doUndo() {
  try { const data=await api('undo','POST',{id:gameId}); if(await refreshFrom(data)){playEffect('undo');setFeedback('Last move undone.');}else setFeedback(errorText(data.error)); }
  catch(e){setFeedback('Server connection lost.');}
}
async function doRestart() {
  if(!confirm('Restart this puzzle from the beginning?'))return;
  try { const data=await api('restart','POST',{id:gameId}); if(await refreshFrom(data)){startTimer(true);selectedTower=null;setFeedback('Fresh start! You’ve got this.');} }
  catch(e){setFeedback('Server connection lost.');}
}
function pauseGame(){if(mode!=='single')return;playEffect('pause');pauseTimer();paused=true;$('pauseOverlay').classList.remove('hidden');}
function resumeGame(){paused=false;startedAt=Date.now();timerHandle=setInterval(()=>$('timerValue').textContent=formatTime(elapsed()),250);$('pauseOverlay').classList.add('hidden');}
function leaveGame(){stopTimer();paused=false;gameId=null;state=null;selectedTower=null;$('celebration').classList.add('hidden');showScreen('homeScreen');}

$('singleStart').addEventListener('click',()=>showSetup('single'));
$('multiStart').addEventListener('click',()=>showSetup('multi'));
$('brandHome').addEventListener('click',e=>{e.preventDefault();leaveGame();});
$('setupBack').addEventListener('click',()=>showScreen('homeScreen'));
$('playerCount').addEventListener('change',renderNameInputs);
$('difficultyChoices').addEventListener('click',e=>{const b=e.target.closest('[data-level]');if(!b)return;difficulty=b.dataset.level;document.querySelectorAll('.difficulty').forEach(x=>x.classList.toggle('selected',x===b));});
$('createGame').addEventListener('click',createGame);
document.querySelectorAll('.tower').forEach(t=>{
  t.addEventListener('click',()=>chooseTower(t.dataset.tower));
  t.addEventListener('dragover',e=>e.preventDefault());
  t.addEventListener('drop',e=>{e.preventDefault();const from=e.dataTransfer.getData('text/plain');if(from)move(from,t.dataset.tower);});
});
$('board').addEventListener('pointerdown',e=>{
  const disk=e.target.closest('.disk'); if(!disk||paused||!state||state.status!=='playing')return;
  const tower=disk.closest('.tower'); const name=tower.dataset.tower;
  const towerIndex=['a','b','c'].indexOf(name), list=state.towers[towerIndex]||[];
  if(!list.length || Number(list[0])!==Number(disk.dataset.disk))return;
  isDragging=true; e.target.classList.add('dragging'); selectedTower=name;
});
document.addEventListener('pointerup',e=>{
  if(!isDragging)return; isDragging=false;
  document.querySelectorAll('.disk.dragging').forEach(d=>d.classList.remove('dragging'));
  const target=e.target.closest('.tower');
  if(target && selectedTower && target.dataset.tower!==selectedTower)move(selectedTower,target.dataset.tower);
  else renderBoard();
});
$('undoBtn').addEventListener('click',doUndo); $('restartBtn').addEventListener('click',doRestart);
$('pauseBtn').addEventListener('click',pauseGame); $('resumeBtn').addEventListener('click',resumeGame);
$('quitGame').addEventListener('click',leaveGame); $('readyBtn').addEventListener('click',readyNext);
$('playAgain').addEventListener('click',()=>showSetup('single')); $('resultHome').addEventListener('click',leaveGame);
$('newMatch').addEventListener('click',()=>showSetup('multi'));
renderNameInputs();


// Independent audio preferences: players choose background music and sound effects separately.
const backgroundMusic = document.getElementById('backgroundMusic');
const musicToggle = document.getElementById('musicToggle');
const effectsToggle = document.getElementById('effectsToggle');
let musicEnabled = false;
let effectsEnabled = true;
let audioContext = null;
backgroundMusic.volume = 0.25;

function updateAudioButtons() {
  musicToggle.textContent = musicEnabled ? '♫ Music: On' : '♫ Music: Off';
  musicToggle.setAttribute('aria-pressed', String(musicEnabled));
  effectsToggle.textContent = effectsEnabled ? '♪ Effects: On' : '♪ Effects: Off';
  effectsToggle.setAttribute('aria-pressed', String(effectsEnabled));
}

musicToggle.addEventListener('click', async () => {
  if (musicEnabled) {
    backgroundMusic.pause();
    musicEnabled = false;
  } else {
    try {
      await backgroundMusic.play();
      musicEnabled = true;
    } catch (error) {
      musicEnabled = false;
      setFeedback('Music could not start. Please try clicking Music again.');
    }
  }
  updateAudioButtons();
});

effectsToggle.addEventListener('click', () => {
  effectsEnabled = !effectsEnabled;
  updateAudioButtons();
  if (effectsEnabled) playEffect('select');
});

function playEffect(kind = 'select') {
  if (!effectsEnabled) return;
  try {
    const AudioCtx = window.AudioContext || window.webkitAudioContext;
    if (!AudioCtx) return;
    audioContext ||= new AudioCtx();
    if (audioContext.state === 'suspended') audioContext.resume();
    const now = audioContext.currentTime;
    const patterns = {
      select: [[660, 0, 0.07]],
      move: [[523, 0, 0.08], [784, 0.075, 0.1]],
      error: [[220, 0, 0.16]],
      undo: [[587, 0, 0.08], [440, 0.08, 0.1]],
      pause: [[440, 0, 0.12]],
      victory: [[523, 0, 0.12], [659, 0.12, 0.12], [784, 0.24, 0.2]]
    };
    (patterns[kind] || patterns.select).forEach(([frequency, delay, duration]) => {
      const oscillator = audioContext.createOscillator();
      const gain = audioContext.createGain();
      oscillator.type = 'sine';
      oscillator.frequency.value = frequency;
      gain.gain.setValueAtTime(0.0001, now + delay);
      gain.gain.exponentialRampToValueAtTime(0.09, now + delay + 0.012);
      gain.gain.exponentialRampToValueAtTime(0.0001, now + delay + duration);
      oscillator.connect(gain);
      gain.connect(audioContext.destination);
      oscillator.start(now + delay);
      oscillator.stop(now + delay + duration + 0.02);
    });
  } catch (error) { /* Audio is optional; gameplay continues without it. */ }
}

updateAudioButtons();
