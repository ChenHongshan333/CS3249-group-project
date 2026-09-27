import { useEffect, useMemo, useRef, useState } from 'react'
import {
  ArrowLeft, ArrowRight, Bell, BookOpen, Camera, Check, CheckCircle2, ChefHat,
  ChevronRight, CircleHelp, Clock3, Copy, Download, Flame, Heart, Home,
  Link2, MessageCircle, Mic, MicOff, MoreHorizontal, Pause, Play, Plus,
  RotateCcw, Search, Send, Settings2, ShieldCheck, Sparkles,
  Users, UtensilsCrossed, Video, VideoOff, Volume2, VolumeX, X,
} from 'lucide-react'
import { recipes, type Mode, type Screen } from './data'

type Preferences = { level: string; diet: string; voice: boolean; captions: boolean; camera: boolean }
type Message = { from: 'ai' | 'user' | 'partner'; text: string }
type HistoryItem = { id: string; recipe: string; date: string; mode: Mode; partner: string }

const defaultPreferences: Preferences = { level: 'I know a few basics', diet: 'No restrictions', voice: true, captions: true, camera: true }
const modeName = (mode: Mode) => mode === 'solo' ? 'Solo cooking' : mode === 'offline' ? 'Same kitchen' : 'Online with a friend'
const stored = <T,>(key: string, fallback: T): T => {
  try { return JSON.parse(localStorage.getItem(key) || '') as T } catch { return fallback }
}

function App() {
  const [screen, setScreen] = useState<Screen>('home')
  const [welcome, setWelcome] = useState(!stored('cookalong.seen', false))
  const [preferences, setPreferences] = useState<Preferences>(() => stored('cookalong.preferences', defaultPreferences))
  const [recipeId, setRecipeId] = useState('salad')
  const [mode, setMode] = useState<Mode>('online')
  const [joinCode] = useState(() => String(Math.floor(1000 + Math.random() * 9000)))
  const [partnerReady, setPartnerReady] = useState(false)
  const [ready, setReady] = useState(false)
  const [step, setStep] = useState(0)
  const [paused, setPaused] = useState(false)
  const [cameraOn, setCameraOn] = useState(true)
  const [micOn, setMicOn] = useState(true)
  const [speakerOn, setSpeakerOn] = useState(true)
  const [cameraCheck, setCameraCheck] = useState(false)
  const [messages, setMessages] = useState<Message[]>([])
  const [draft, setDraft] = useState('')
  const [toast, setToast] = useState('')
  const [history, setHistory] = useState<HistoryItem[]>(() => stored('cookalong.history', []))
  const [search, setSearch] = useState('')
  const [videoUrl, setVideoUrl] = useState('')
  const [postText, setPostText] = useState('')
  const [posts, setPosts] = useState<string[]>(() => stored('cookalong.posts', []))
  const [recording, setRecording] = useState(false)
  const [seconds, setSeconds] = useState(0)
  const [timer, setTimer] = useState<number | null>(null)
  const [importUrl, setImportUrl] = useState('')
  const [importOpen, setImportOpen] = useState(false)
  const transcriptEnd = useRef<HTMLDivElement>(null)
  const recipe = useMemo(() => recipes.find(item => item.id === recipeId) || recipes[0], [recipeId])
  const visibleRecipes = recipes.filter(item => `${item.name} ${item.ingredients.join(' ')}`.toLowerCase().includes(search.toLowerCase()))

  useEffect(() => { localStorage.setItem('cookalong.preferences', JSON.stringify(preferences)) }, [preferences])
  useEffect(() => { localStorage.setItem('cookalong.history', JSON.stringify(history)) }, [history])
  useEffect(() => { localStorage.setItem('cookalong.posts', JSON.stringify(posts)) }, [posts])
  useEffect(() => { if (!toast) return; const id = window.setTimeout(() => setToast(''), 3200); return () => clearTimeout(id) }, [toast])
  useEffect(() => {
    if (screen !== 'cook' || paused) return
    const id = window.setInterval(() => setSeconds(value => value + 1), 1000)
    return () => clearInterval(id)
  }, [screen, paused])
  useEffect(() => {
    if (timer === null || paused) return
    const id = window.setInterval(() => setTimer(value => value === null ? null : Math.max(0, value - 1)), 1000)
    return () => clearInterval(id)
  }, [timer !== null, paused])
  useEffect(() => { if (timer === 0) { setToast('Timer finished — check your food.'); setTimer(null) } }, [timer])
  useEffect(() => { transcriptEnd.current?.scrollIntoView({ behavior: 'smooth', block: 'end' }) }, [messages])

  const say = (text: string) => {
    if (!preferences.voice || !speakerOn || !('speechSynthesis' in window)) return
    window.speechSynthesis.cancel()
    const utterance = new SpeechSynthesisUtterance(text)
    utterance.rate = 0.92
    window.speechSynthesis.speak(utterance)
  }
  const showInstruction = (index: number) => {
    const instruction = recipe.steps[index].instruction
    setMessages(current => [...current, { from: 'ai', text: instruction }])
    say(instruction)
  }
  const begin = () => {
    setStep(0); setSeconds(0); setPaused(false); setCameraCheck(false); setTimer(null)
    setMessages([{ from: 'ai', text: `Let's make ${recipe.name.toLowerCase()}! ${recipe.steps[0].instruction}` }])
    setScreen('cook')
    say(recipe.steps[0].instruction)
  }
  const nextStep = () => {
    if (paused) return
    if (step === recipe.steps.length - 1) {
      setHistory(current => [{ id: `${Date.now()}`, recipe: recipe.name, date: new Date().toLocaleDateString('en-SG', { day: 'numeric', month: 'short', year: 'numeric' }), mode, partner: mode === 'solo' ? '' : 'Maya' }, ...current])
      setScreen('finish'); window.speechSynthesis?.cancel(); return
    }
    const newStep = step + 1
    setStep(newStep); setCameraCheck(false)
    setMessages(current => [...current, { from: 'user', text: 'Done with this step ✓' }])
    showInstruction(newStep)
  }
  const ask = (text: string) => {
    const question = text.trim()
    if (!question) return
    setMessages(current => [...current, { from: 'user', text: question }])
    setDraft('')
    let answer = `Good question. ${recipe.steps[step].tip} When you're ready, return to this step: ${recipe.steps[step].instruction}`
    if (/timer|minute|time/i.test(question)) { setTimer(3 * 60); answer = 'I set a three-minute timer. You can keep cooking; I will let you know when it finishes.' }
    if (/allerg|substitut|replace/i.test(question)) answer = 'I cannot verify that a substitute is safe for your allergy. Check the ingredient label and avoid it if you are unsure. We can pause while you find a safe option.'
    if (/repeat|again/i.test(question)) answer = recipe.steps[step].instruction
    if (/next|done|finished/i.test(question)) answer = `Nice work. To move on, tap “${step === recipe.steps.length - 1 ? 'Finish cooking' : 'Step complete'}” below.`
    window.setTimeout(() => { setMessages(current => [...current, { from: 'ai', text: answer }]); say(answer) }, 350)
  }
  const repeat = () => { showInstruction(step); setToast('Instruction repeated') }
  const simulateVoice = () => {
    if (!micOn) { setToast('Turn your microphone on first.'); return }
    const Recognition = (window as unknown as { SpeechRecognition?: new () => SpeechRecognitionLike; webkitSpeechRecognition?: new () => SpeechRecognitionLike }).SpeechRecognition
      || (window as unknown as { webkitSpeechRecognition?: new () => SpeechRecognitionLike }).webkitSpeechRecognition
    if (!Recognition) { ask('How do I know this step is done?'); setToast('Demo voice question added to the conversation.'); return }
    const recognition = new Recognition()
    recognition.lang = 'en-US'; recognition.onresult = event => ask(event.results[0][0].transcript)
    recognition.onerror = () => setToast('Voice unavailable. Use the text field below.')
    recognition.start(); setToast('Listening… ask your cooking question.')
  }
  const exportVideo = async () => {
    if (!('MediaRecorder' in window) || !HTMLCanvasElement.prototype.captureStream) { setToast('Video export needs a recent Chrome or Edge browser.'); return }
    setRecording(true)
    try {
      const canvas = document.createElement('canvas'); canvas.width = 720; canvas.height = 1280
      const ctx = canvas.getContext('2d')!
      const stream = canvas.captureStream(24)
      const mime = ['video/webm;codecs=vp9', 'video/webm;codecs=vp8', 'video/webm'].find(type => MediaRecorder.isTypeSupported(type)) || ''
      const recorder = new MediaRecorder(stream, mime ? { mimeType: mime } : undefined)
      const chunks: BlobPart[] = []
      recorder.ondataavailable = event => { if (event.data.size) chunks.push(event.data) }
      recorder.onstop = () => {
        stream.getTracks().forEach(track => track.stop())
        const url = URL.createObjectURL(new Blob(chunks, { type: recorder.mimeType || 'video/webm' }))
        const link = document.createElement('a'); link.href = url; link.download = `CookAlong-${recipe.id}-recap.webm`; link.click()
        window.setTimeout(() => URL.revokeObjectURL(url), 30_000)
        setRecording(false); setToast('Demo recap video downloaded!')
      }
      recorder.start()
      const start = performance.now()
      const draw = () => {
        const elapsed = performance.now() - start
        const phase = Math.min(2, Math.floor(elapsed / 1450))
        const palette = ['#c44a3a', '#d97a2b', '#6faf4f']
        ctx.fillStyle = '#fbf7ed'; ctx.fillRect(0, 0, 720, 1280)
        ctx.fillStyle = palette[phase]; ctx.fillRect(0, 0, 720, 35)
        ctx.fillStyle = '#28332a'; ctx.font = 'bold 45px system-ui'; ctx.fillText('CookAlong', 64, 115)
        ctx.font = '185px system-ui'; ctx.textAlign = 'center'; ctx.fillText(recipe.icon, 360, 510)
        ctx.fillStyle = '#28332a'; ctx.font = 'bold 49px system-ui'; ctx.fillText(['The little steps', 'A shared moment', 'Made by you!'][phase], 360, 650)
        ctx.font = '33px system-ui'; ctx.fillText(recipe.name, 360, 715)
        ctx.fillStyle = '#6c756a'; ctx.font = '28px system-ui'; ctx.fillText(mode === 'solo' ? 'One delicious accomplishment' : 'Better together with Maya', 360, 790)
        ctx.textAlign = 'left'; ctx.fillStyle = '#d97a2b'; ctx.fillRect(64, 1120, Math.min(590, 590 * elapsed / 4350), 10)
        if (elapsed < 4350) requestAnimationFrame(draw)
        else recorder.stop()
      }
      draw()
    } catch { setRecording(false); setToast('Could not export video in this browser.') }
  }
  const back = () => {
    if (screen === 'cook') { setPaused(true); setToast('Session paused. Resume from the cooking screen.'); return }
    setScreen(({ preferences: 'home', recipes: 'home', mode: 'recipes', pair: 'mode', finish: 'home', history: 'home', community: 'home', profile: 'home', home: 'home' } as Record<Screen, Screen>)[screen] || 'home')
  }

  return <div className="stage"><div className="phone">
    <div className="status-bar"><span>9:41</span><div className="island" /><span className="status-icons">●●● ▰</span></div>
    {screen === 'home' && <>
      <main className="screen home-screen">
        <div className="topline"><div className="brand"><span className="brand-mark"><UtensilsCrossed size={19} strokeWidth={2.6} /></span><span>CookAlong</span></div><button className="icon-button" aria-label="Open profile" onClick={() => setScreen('profile')}><span className="avatar">H</span></button></div>
        <div className="hero-intro"><div className="eyebrow"><span className="eyebrow-dot" /> YOUR KITCHEN COMPANION</div><h1>Good food tastes<br /><em>better together.</em></h1><p>A little guidance and a friend by your side. What will we make today?</p></div>
        <div className="orbit-card"><div className="orbit-spark">✦</div><div className="orbit-line orbit-line-a" /><div className="orbit-line orbit-line-b" /><span className="orbit-pill orbit-pill-one">🥕 Prep</span><span className="orbit-pill orbit-pill-two">🍳 Cook</span><span className="orbit-pill orbit-pill-three">✨ Share</span><div className="orbit-center"><span className="orbit-icon">👩‍🍳</span><strong>Let's cook!</strong><small>one step at a time</small></div></div>
        <button className="primary-button home-start" onClick={() => setScreen('recipes')}>Start cooking <ArrowRight size={20} /></button>
        <div className="section-title"><h2>Your kitchen, your way</h2><span>Explore</span></div>
        <div className="quick-grid"><button onClick={() => setScreen('preferences')}><span className="quick-icon green"><Settings2 size={21} /></span><span>Preferences</span><ChevronRight size={16} /></button><button onClick={() => setScreen('recipes')}><span className="quick-icon yellow"><BookOpen size={21} /></span><span>Recipes</span><ChevronRight size={16} /></button></div>
        <div className="gentle-note"><Heart size={19} /><span>Small steps count. Your next meal can be a fresh start.</span></div>
      </main><Nav screen={screen} go={setScreen} /></>}

    {screen === 'preferences' && <main className="screen has-footer"><Header title="Your preferences" label="MAKE IT YOURS" back={back} /><div className="content-scroll">
      <div className="page-heading"><h1>Cooking should<br /><em>feel good.</em></h1><p>Set things up the way that helps you feel comfortable.</p></div>
      <div className="field-card"><div className="field-heading"><ChefHat size={19} /><strong>Cooking experience</strong></div><div className="option-stack">{['First time cooking', 'I know a few basics'].map(item => <button key={item} className={`radio-row ${preferences.level === item ? 'selected' : ''}`} onClick={() => setPreferences({ ...preferences, level: item })}><span>{item}</span><span className="radio" /></button>)}</div></div>
      <div className="field-card"><div className="field-heading"><Heart size={19} /><strong>Dietary needs</strong></div><div className="chip-list">{['No restrictions', 'Vegetarian', 'Halal', 'Other'].map(item => <button key={item} className={`chip ${preferences.diet === item ? 'chosen' : ''}`} onClick={() => setPreferences({ ...preferences, diet: item })}>{item}</button>)}</div><p className="field-note">Check ingredient labels yourself for allergies or specific dietary needs.</p></div>
      <div className="field-card"><div className="field-heading"><MessageCircle size={19} /><strong>During cooking</strong></div><Toggle label="Read steps aloud" detail="Voice guidance" checked={preferences.voice} onChange={() => setPreferences({ ...preferences, voice: !preferences.voice })} /><Toggle label="Show text captions" detail="Follow along quietly" checked={preferences.captions} onChange={() => setPreferences({ ...preferences, captions: !preferences.captions })} /><Toggle label="Camera check prompts" detail="Simulated for this prototype" checked={preferences.camera} onChange={() => setPreferences({ ...preferences, camera: !preferences.camera })} /></div>
    </div><div className="bottom-action"><button className="primary-button" onClick={() => { setToast('Preferences saved'); setScreen('home') }}>Save preferences <Check size={19} /></button></div></main>}

    {screen === 'recipes' && <main className="screen has-footer"><Header title="Choose a recipe" label="STEP 01 / THE MEAL" back={back} /><div className="content-scroll"><div className="page-heading compact"><h1>What sounds <em>good?</em></h1><p>Pick one meal to make. In a paired session, both cooks follow the same recipe.</p></div><div className="search-box"><Search size={19} /><input aria-label="Search recipes" value={search} onChange={event => setSearch(event.target.value)} placeholder="Search meals or ingredients" /></div><div className="recipe-list">{visibleRecipes.map(item => <button key={item.id} className={`recipe-card ${recipeId === item.id ? 'active' : ''}`} onClick={() => setRecipeId(item.id)}><div className={`food-art ${item.tone}`}><span>{item.icon}</span></div><div className="recipe-info"><strong>{item.name}</strong><span><Clock3 size={14} /> {item.time} min · {item.level}</span><small>{item.ingredients.slice(0, 3).join(' · ')}</small></div><span className="recipe-check">{recipeId === item.id && <Check size={16} />}</span></button>)}{visibleRecipes.length === 0 && <p className="empty-state">No matching recipes. Try another ingredient.</p>}</div><button className="video-import" onClick={() => setImportOpen(true)}><Video size={19} /><span><strong>Have a recipe video?</strong><small>Explore the video input concept</small></span><ChevronRight size={18} /></button></div><div className="bottom-action"><button className="primary-button" onClick={() => setScreen('mode')}>Continue with {recipe.name} <ArrowRight size={19} /></button></div></main>}

    {screen === 'mode' && <main className="screen has-footer"><Header title="Cooking mode" label="STEP 02 / TOGETHERNESS" back={back} /><div className="content-scroll"><div className="page-heading"><h1>How shall we <em>cook?</em></h1><p>Choose the company that feels right today. Your recipe stays the same.</p></div><div className="meal-mini"><span>{recipe.icon}</span><div><small>ON THE MENU</small><strong>{recipe.name}</strong></div><Clock3 size={17} /></div><div className="mode-list"><button className={`mode-card ${mode === 'solo' ? 'active' : ''}`} onClick={() => setMode('solo')}><span className="mode-icon solo"><ChefHat size={25} /></span><span><strong>Just me & CookAlong</strong><small>Go at your own pace with AI guidance.</small></span><span className="radio" /></button><button className={`mode-card ${mode === 'offline' ? 'active' : ''}`} onClick={() => setMode('offline')}><span className="mode-icon offline"><Users size={25} /></span><span><strong>Same kitchen</strong><small>Cook one meal side by side.</small></span><span className="radio" /></button><button className={`mode-card ${mode === 'online' ? 'active' : ''}`} onClick={() => setMode('online')}><span className="mode-icon online"><Video size={25} /></span><span><strong>Online with a friend</strong><small>Share a kitchen moment from afar.</small></span><span className="radio" /></button></div><div className="gentle-note mode-note"><ShieldCheck size={20} /><span>You control the camera and microphone throughout the session.</span></div></div><div className="bottom-action"><button className="primary-button" onClick={() => { setPartnerReady(false); setReady(false); setScreen('pair') }}>{mode === 'solo' ? 'Set up solo session' : 'Continue to pairing'} <ArrowRight size={19} /></button></div></main>}

    {screen === 'pair' && <main className="screen has-footer"><Header title={mode === 'solo' ? 'Ready to cook' : 'Pair your cooking buddy'} label="STEP 03 / GET READY" back={back} /><div className="content-scroll"><div className="page-heading compact"><h1>{mode === 'solo' ? <>Your kitchen, <em>your pace.</em></> : <>A meal is better <em>shared.</em></>}</h1><p>{mode === 'solo' ? 'Take a breath, gather your ingredients, and start whenever you are ready.' : mode === 'offline' ? 'Invite the person beside you to join the same cooking session.' : 'Invite a friend to make this same meal with you, wherever they are.'}</p></div>
      <div className="pair-hero"><div className="pair-avatar you">H</div><span className="pair-bridge">✳</span><div className={`pair-avatar ${partnerReady ? 'friend' : 'waiting'}`}>{mode === 'solo' ? <ChefHat size={26} /> : partnerReady ? 'M' : '?'}</div><p>{mode === 'solo' ? 'CookAlong is ready to guide you.' : partnerReady ? 'Maya is ready to cook with you!' : 'Waiting for your cooking buddy…'}</p></div>
      {mode !== 'solo' && <div className="invite-card"><div className="field-heading"><Link2 size={19} /><strong>Invite with a code</strong></div><p>Share this demo code with your friend. Both cooks make <b>{recipe.name}</b>.</p><div className="code-row"><strong>{joinCode.split('').join(' ')}</strong><button aria-label="Copy invite code" onClick={async () => { try { await navigator.clipboard.writeText(joinCode); setToast('Invite code copied') } catch { setToast(`Invite code: ${joinCode}`) } }}><Copy size={19} /></button></div><button className="text-link" onClick={() => setPartnerReady(true)}>{partnerReady ? '✓ Maya joined the session' : 'Simulate friend joining'} <ArrowRight size={16} /></button></div>}
      <div className="ready-card"><div><strong>Before we begin</strong><p>{recipe.ingredients.join(' · ')}</p></div><button className={`check-row ${ready ? 'done' : ''}`} onClick={() => setReady(!ready)}><span className="square-check">{ready && <Check size={16} />}</span> I have my ingredients ready</button></div>
      {mode === 'online' && <p className="fine-print"><Camera size={15} /> Two camera tiles in the next screen are simulated, including your friend's feed.</p>}
    </div><div className="bottom-action"><button className="primary-button" disabled={!ready || (mode !== 'solo' && !partnerReady)} onClick={begin}>Start cooking <ArrowRight size={19} /></button><span className="action-hint">{!ready ? 'Check your ingredients to continue' : mode !== 'solo' && !partnerReady ? 'Waiting for your friend' : 'Everything is ready'}</span></div></main>}

    {screen === 'cook' && <main className="screen cooking-screen"><div className="cook-top"><button className="icon-button back-round" aria-label="Back to session" onClick={back}><ArrowLeft size={20} /></button><div><small>NOW COOKING</small><strong>{recipe.name}</strong></div><button className="icon-button back-round" aria-label="More session options" onClick={() => setToast(`${modeName(mode)} · ${Math.floor(seconds / 60)} min elapsed`)}><MoreHorizontal size={21} /></button></div>
      <div className="cook-scroll"><div className="step-overview"><div className="step-meta"><span>STEP {step + 1} OF {recipe.steps.length}</span><span>{Math.round((step + 1) / recipe.steps.length * 100)}%</span></div><div className="progress-track"><span style={{ width: `${(step + 1) / recipe.steps.length * 100}%` }} /></div><h1>{recipe.steps[step].title}</h1><p>Take it one step at a time. We're right here with you.</p></div>
      <div className={`camera-grid ${mode === 'solo' ? 'single' : ''}`}><div className={`camera-tile yours ${!cameraOn ? 'camera-off' : ''}`}><div className="tile-noise" /><span className="camera-label"><span className="live-dot" /> YOU {cameraOn ? '· DEMO VIEW' : '· CAMERA OFF'}</span><span className="tile-center">{cameraOn ? recipe.icon : <VideoOff size={30} />}</span></div>{mode !== 'solo' && <div className="camera-tile partner"><div className="tile-noise" /><span className="camera-label"><span className="live-dot green-dot" /> {mode === 'online' ? 'MAYA · DEMO VIEW' : 'BOTH COOKS'}</span><span className="tile-center">{mode === 'online' ? '👩🏽‍🍳' : '👩‍🍳'}</span></div>}</div>
      <div className="session-strip"><span><Users size={16} /> {modeName(mode)}</span><span><Clock3 size={15} /> {Math.floor(seconds / 60)}:{String(seconds % 60).padStart(2, '0')}</span>{timer !== null && <span><Bell size={15} /> {Math.floor(timer / 60)}:{String(timer % 60).padStart(2, '0')}</span>}</div>
      <div className="guide-panel"><div className="guide-head"><span className="ai-badge"><Sparkles size={16} /></span><strong>CookAlong says</strong><span>AI GUIDE</span></div><p>{recipe.steps[step].instruction}</p><div className="guide-tip"><Flame size={16} /> {recipe.steps[step].tip}</div></div>
      <div className="cook-actions"><button onClick={repeat}><RotateCcw size={18} /> Repeat</button><button onClick={() => setPaused(!paused)}>{paused ? <Play size={18} /> : <Pause size={18} />}{paused ? 'Resume' : 'Pause'}</button><button onClick={() => ask('How do I know this step is done?')}><CircleHelp size={18} /> Ask</button></div>
      {paused && <div className="state-card paused"><Pause size={19} /><div><strong>Session paused</strong><p>Take your time. Tap Resume when you are ready.</p></div></div>}
      {preferences.camera && <button className="camera-check" onClick={() => setCameraCheck(!cameraCheck)}><Camera size={19} /> {cameraCheck ? 'Hide camera check' : 'Check my progress'} <ChevronRight size={17} /></button>}
      {cameraCheck && <div className="state-card check-result"><ShieldCheck size={20} /><div><strong>Demo camera check</strong><p>This is a simulated result: {recipe.steps[step].check} Please verify it yourself before moving on. A camera alone cannot confirm food safety.</p></div></div>}
      <div className="transcript-panel"><div className="transcript-title"><MessageCircle size={17} /> Conversation <span>CAPTIONS</span></div><div className="transcript-messages">{messages.map((message, index) => <div className={`bubble ${message.from}`} key={`${index}-${message.from}`}>{message.text}</div>)}<div ref={transcriptEnd} /></div></div>
      <button className="step-button" onClick={nextStep} disabled={paused}>{step === recipe.steps.length - 1 ? 'Finish cooking' : 'Step complete'} <ArrowRight size={19} /></button>
      </div><div className="composer"><div className="control-row"><button aria-label={cameraOn ? 'Turn camera off' : 'Turn camera on'} className={!cameraOn ? 'off' : ''} onClick={() => setCameraOn(!cameraOn)}>{cameraOn ? <Video size={20} /> : <VideoOff size={20} />}</button><button aria-label={micOn ? 'Mute microphone' : 'Unmute microphone'} className={!micOn ? 'off' : ''} onClick={() => setMicOn(!micOn)}>{micOn ? <Mic size={20} /> : <MicOff size={20} />}</button><button aria-label={speakerOn ? 'Mute assistant' : 'Unmute assistant'} className={!speakerOn ? 'off' : ''} onClick={() => { setSpeakerOn(!speakerOn); window.speechSynthesis?.cancel() }}>{speakerOn ? <Volume2 size={20} /> : <VolumeX size={20} />}</button><button aria-label="Set three-minute timer" onClick={() => { setTimer(180); setToast('Three-minute timer started') }}><Clock3 size={20} /></button></div><form onSubmit={event => { event.preventDefault(); ask(draft) }}><button type="button" className="voice-button" aria-label="Ask with voice" onClick={simulateVoice}><Mic size={19} /></button><input aria-label="Ask CookAlong" value={draft} onChange={event => setDraft(event.target.value)} placeholder="Ask anything, anytime…" /><button type="submit" aria-label="Send question" className="send-button"><Send size={19} /></button></form></div></main>}

    {screen === 'finish' && <main className="screen has-footer finish-screen"><Header title="A meal well made" label="SESSION COMPLETE" back={() => setScreen('home')} /><div className="content-scroll"><div className="confetti">✦ <span>✳</span> ✦</div><div className="finish-heading"><span className="finish-emoji">{recipe.icon}</span><h1>You made it!</h1><p>{mode === 'solo' ? 'One small cooking win, made by you.' : 'A little teamwork and a delicious meal to show for it.'}</p></div><div className="finish-stats"><div><strong>{recipe.steps.length}</strong><span>steps completed</span></div><div><strong>{Math.max(1, Math.ceil(seconds / 60))}</strong><span>minutes together</span></div><div><strong>{mode === 'solo' ? '1' : '2'}</strong><span>{mode === 'solo' ? 'happy cook' : 'happy cooks'}</span></div></div><div className="recap-card"><div className="recap-art">{recipe.icon}<span><Play size={23} fill="currentColor" /></span></div><div className="recap-details"><small>YOUR COOKING STORY</small><strong>{recipe.name}</strong><p>A short animated recap of this demo session. No camera footage is recorded.</p><button onClick={exportVideo} disabled={recording}>{recording ? 'Creating video…' : 'Export demo video'} <Download size={16} /></button></div></div><div className="share-prompt"><Heart size={20} /><div><strong>A moment worth sharing</strong><p>{mode === 'solo' ? 'Celebrate what you made. Your meal is saved in History.' : 'Show Maya your finished plate and celebrate the little win together.'}</p></div></div></div><div className="bottom-action"><button className="primary-button" onClick={() => { setScreen('home'); setPartnerReady(false); setReady(false) }}>Back to home <Home size={19} /></button><button className="secondary-link" onClick={() => setScreen('history')}>View cooking history</button></div></main>}

    {screen === 'history' && <><main className="screen"><Header title="Cooking history" label="YOUR LITTLE WINS" back={back} /><div className="content-scroll"><div className="page-heading compact"><h1>Look what you've <em>made.</em></h1><p>Every meal is a step forward.</p></div>{history.length ? <div className="history-list">{history.map(item => <div className="history-card" key={item.id}><span className="history-icon">{recipes.find(r => r.name === item.recipe)?.icon || '🍽️'}</span><div><strong>{item.recipe}</strong><small>{item.date} · {modeName(item.mode)}{item.partner ? ` · ${item.partner}` : ''}</small></div><CheckCircle2 size={18} /></div>)}</div> : <div className="empty-panel"><BookOpen size={34} /><strong>Your story starts here.</strong><p>Cook a meal and it will appear in your history.</p><button className="small-primary" onClick={() => setScreen('recipes')}>Choose a recipe <ArrowRight size={16} /></button></div>}</div></main><Nav screen={screen} go={setScreen} /></>}

    {screen === 'community' && <><main className="screen"><Header title="Community" label="COOKING TOGETHER" back={back} /><div className="content-scroll"><div className="page-heading compact"><h1>From our <em>kitchens.</em></h1><p>Share the little moments that make cooking fun.</p></div><div className="community-compose"><span className="avatar">H</span><input aria-label="Write a community post" value={postText} onChange={event => setPostText(event.target.value)} placeholder="What did you cook today?" /><button aria-label="Post" onClick={() => { if (postText.trim()) { setPosts([postText.trim(), ...posts]); setPostText(''); setToast('Post shared in this demo') } }}><Plus size={20} /></button></div><div className="post-card"><div className="post-author"><span className="avatar friend-avatar">M</span><div><strong>Maya</strong><small>Today · CookAlong community</small></div></div><div className="post-visual">🥗<span>GOOD FOOD,<br />GOOD COMPANY.</span></div><p>First salad bowl with a friend! The small steps made it feel so much easier. 🌿</p><span className="post-love"><Heart size={17} /> 12 little hearts</span></div>{posts.map((item, index) => <div className="post-card" key={`${item}-${index}`}><div className="post-author"><span className="avatar">H</span><div><strong>You</strong><small>Just now · Demo post</small></div></div><p>{item}</p><span className="post-love"><Heart size={17} /> Your cooking story</span></div>)}</div></main><Nav screen={screen} go={setScreen} /></>}

    {screen === 'profile' && <><main className="screen"><Header title="Your profile" label="MY KITCHEN" back={back} /><div className="content-scroll"><div className="profile-hero"><span className="profile-avatar">H</span><h1>Hi, home cook!</h1><p>Every recipe is a new adventure.</p></div><div className="profile-stat"><strong>{history.length}</strong><span>meals made</span><strong>{new Set(history.map(item => item.recipe)).size}</strong><span>recipes explored</span></div><div className="profile-links"><button onClick={() => setScreen('preferences')}><Settings2 size={20} /> Cooking preferences <ChevronRight size={19} /></button><button onClick={() => setScreen('history')}><BookOpen size={20} /> Cooking history <ChevronRight size={19} /></button><button onClick={() => setScreen('community')}><Users size={20} /> Community <ChevronRight size={19} /></button></div><div className="gentle-note"><Sparkles size={19} /><span>CookAlong is an AI guide. Check food safety and dietary needs yourself.</span></div></div></main><Nav screen={screen} go={setScreen} /></>}

    {welcome && <div className="modal-backdrop"><div className="welcome-modal"><button aria-label="Close welcome" onClick={() => { setWelcome(false); localStorage.setItem('cookalong.seen', 'true') }}><X size={20} /></button><span className="welcome-symbol">👋</span><span className="eyebrow">HELLO, HOME COOK</span><h2>Meet CookAlong.</h2><p>Your friendly AI cooking companion. Follow simple steps, ask questions, and cook with a friend wherever you are.</p><div className="welcome-limit"><ShieldCheck size={19} /><span>I'm an AI guide. I can help you through a recipe, but I can't guarantee food is safe or diagnose an allergy.</span></div><button className="primary-button" onClick={() => { setWelcome(false); localStorage.setItem('cookalong.seen', 'true') }}>Let's get started <ArrowRight size={19} /></button></div></div>}
    {importOpen && <div className="modal-backdrop"><div className="import-modal"><button className="modal-close" aria-label="Close" onClick={() => setImportOpen(false)}><X size={20} /></button><span className="import-icon"><Video size={26} /></span><h2>Recipe video input</h2><p>Explore how a cooking video could become a step-by-step recipe. This prototype uses a sample recipe for the demonstration.</p><label htmlFor="video-url">Video link</label><input id="video-url" type="url" value={importUrl} onChange={event => setImportUrl(event.target.value)} placeholder="https://example.com/recipe-video" /><button className="primary-button" disabled={!importUrl.trim()} onClick={() => { setVideoUrl(importUrl); setImportOpen(false); setRecipeId('noodles'); setToast('Demo recipe loaded: One-pan veggie noodles') }}>Preview example recipe <ArrowRight size={18} /></button>{videoUrl && <small>Previous example: {videoUrl}</small>}</div></div>}
    {toast && <div className="toast" role="status"><CheckCircle2 size={17} /> {toast}</div>}
    <div className="home-indicator"><span /></div>
  </div><div className="stage-caption"><span className="caption-dot" /> INTERACTIVE PROTOTYPE <span>·</span> iPhone 17</div></div>
}

type SpeechRecognitionLike = { lang: string; onresult: (event: { results: { [index: number]: { [index: number]: { transcript: string } } } }) => void; onerror: () => void; start: () => void }
function Header({ title, label, back }: { title: string; label: string; back: () => void }) { return <div className="page-header"><button className="back-button" aria-label="Go back" onClick={back}><ArrowLeft size={20} /></button><div><small>{label}</small><strong>{title}</strong></div><span className="header-decoration">✳</span></div> }
function Toggle({ label, detail, checked, onChange }: { label: string; detail: string; checked: boolean; onChange: () => void }) { return <button className="toggle-row" role="switch" aria-checked={checked} onClick={onChange}><span><strong>{label}</strong><small>{detail}</small></span><span className={`toggle ${checked ? 'on' : ''}`}><i /></span></button> }
function Nav({ screen, go }: { screen: Screen; go: (screen: Screen) => void }) { return <nav className="bottom-nav"><button className={screen === 'home' ? 'active' : ''} onClick={() => go('home')}><Home size={21} /><span>Home</span></button><button className={screen === 'recipes' ? 'active' : ''} onClick={() => go('recipes')}><BookOpen size={21} /><span>Recipes</span></button><button className="nav-cook" aria-label="Start cooking" onClick={() => go('recipes')}><Plus size={27} /></button><button className={screen === 'history' ? 'active' : ''} onClick={() => go('history')}><Clock3 size={21} /><span>History</span></button><button className={screen === 'community' ? 'active' : ''} onClick={() => go('community')}><Users size={21} /><span>Community</span></button></nav> }

export default App
