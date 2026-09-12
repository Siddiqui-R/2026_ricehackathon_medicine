// Purpose: Present the original small product illustrations in a normally scrolling /test tour.
// Inputs: Native scroll timelines, local sample-record filters, source visibility and transcript/summary selections.
// Outputs: Layered records, an inspectable visit brief and a switchable appointment memory.
// Side effects: Local preview state only. CSS assembles and separates the pieces with native scroll progress.

import { useState, type CSSProperties } from 'react';
import {
  ArrowDown,
  ArrowUpRight,
  Check,
  FileText,
  FolderOpen,
  MessageCircle,
  Mic,
  Pause,
  Play,
  Search,
  X,
} from 'lucide-react';
import { Landing } from './Landing';
import { Brand } from '../components/Brand';
import '../styles/test-landing.css';

// MARK: - Small working previews show existing capabilities using local illustrative content
const documents = [
  { title: 'Visit notes', detail: 'Your original, always within reach', type: 'Notes', icon: MessageCircle },
  { title: 'Lab results.pdf', detail: 'Search the words inside', type: 'PDF', icon: FileText },
  { title: 'Medication list.pdf', detail: 'Ready for your next conversation', type: 'PDF', icon: FileText },
];
function RecordsPreview() {
  const [filter, setFilter] = useState('All');
  return (
    <div className="tl-stage tl-records-stage">
      <div className="tl-orbit tl-orbit-one" aria-hidden="true" />
      <div className="tl-orbit tl-orbit-two" aria-hidden="true" />
      <div className="tl-back-sheet tl-layer" aria-hidden="true">
        <FileText />
        <span />
        <span />
        <span />
      </div>
      <div className="tl-record-panel tl-layer">
        <div className="tl-panel-top">
          <FolderOpen size={20} />
          <span>Records</span>
          <span className="tl-count">3 sources</span>
        </div>
        <div className="tl-filter" role="group" aria-label="Filter sample records">
          {['All', 'PDF', 'Notes'].map((item) => (
            <button key={item} aria-pressed={filter === item} onClick={() => setFilter(item)}>
              {item}
            </button>
          ))}
        </div>
        <div className="tl-document-list" aria-live="polite">
          {documents
            .filter((document) => filter === 'All' || document.type === filter)
            .map((document) => (
              <div className="tl-document" key={document.title}>
                <span className="tl-file-icon">
                  <document.icon size={20} />
                </span>
                <div>
                  <strong>{document.title}</strong>
                  <span>{document.detail}</span>
                </div>
                <ArrowUpRight size={15} aria-hidden="true" />
              </div>
            ))}
        </div>
        <div className="tl-panel-note">
          <Check size={14} /> Originals stay with their source
        </div>
      </div>
      <div className="tl-search-float tl-layer">
        <Search size={17} />
        <span>A name. A note. A moment.</span>
        <kbd>Find it.</kbd>
      </div>
      <div className="tl-paper-tag tl-layer">
        <FileText size={16} />
        <span>PDFs, images & notes</span>
      </div>
    </div>
  );
}
function BriefPreview() {
  const [sourceOpen, setSourceOpen] = useState(false);
  return (
    <div className="tl-stage tl-brief-stage">
      <div className="tl-brief-halo" aria-hidden="true" />
      <div className="tl-brief-shadow tl-layer" aria-hidden="true" />
      <div className="tl-brief-paper tl-layer">
        <div className="tl-brief-brand">
          <Brand compact />
          <span>Your next appointment</span>
          <ArrowUpRight size={17} />
        </div>
        <h3>A clearer starting point.</h3>
        <p>A few things to bring into the conversation.</p>
        <div className="tl-brief-section">
          <span className="tl-small-title">From your records</span>
          <blockquote>“Bring your updated medication list.”</blockquote>
          <button
            className="tl-citation"
            aria-expanded={sourceOpen}
            aria-controls="tour-source"
            onClick={() => setSourceOpen(!sourceOpen)}
          >
            <FileText size={13} /> Visit notes · page 1 <ArrowUpRight size={12} />
          </button>
        </div>
        <div className="tl-brief-section">
          <span className="tl-small-title">Your questions</span>
          <p className="tl-question">
            <span>01</span> What should we focus on today?
          </p>
          <p className="tl-question">
            <span>02</span> What should I keep track of next?
          </p>
        </div>
        <div className="tl-brief-bottom">
          <Check size={14} /> A brief you can review, edit & bring
        </div>
      </div>
      <div
        className={`tl-source-card tl-layer ${sourceOpen ? 'is-open' : ''}`}
        id="tour-source"
        hidden={!sourceOpen}
      >
        <div>
          <strong>The original source</strong>
          <button onClick={() => setSourceOpen(false)} aria-label="Close source preview">
            <X size={16} />
          </button>
        </div>
        <span>Visit notes · page 1</span>
        <p>Next visit</p>
        <mark>Bring your updated medication list.</mark>
        <p>Write down the questions you would like to discuss.</p>
      </div>
      {!sourceOpen && (
        <div className="tl-citation-hint tl-layer">
          <span aria-hidden="true">↖</span> Tap the citation. See the source.
        </div>
      )}
    </div>
  );
}
const waveform = Array.from(
  { length: 49 },
  (_, index) => 12 + Math.abs(Math.sin(index * 1.7) * Math.cos(index * 0.43)) * 46,
);
function MemoryPreview() {
  const [view, setView] = useState('Summary');
  return (
    <div className="tl-stage tl-memory-stage">
      <div className="tl-memory-disc" aria-hidden="true">
        <div />
        <div />
      </div>
      <div className="tl-audio-card tl-layer">
        <div className="tl-audio-heading">
          <span className="tl-mic">
            <Mic size={20} />
          </span>
          <div>
            <strong>Your appointment</strong>
            <span>Saved recording</span>
          </div>
          <span className="tl-audio-time">12:48</span>
        </div>
        <div className="tl-wave" aria-hidden="true">
          {waveform.map((height, index) => (
            <span key={index} style={{ '--bar-height': `${height}px` } as CSSProperties} />
          ))}
        </div>
        <div className="tl-audio-scale">
          <span>00:00</span>
          <span>The conversation, kept close.</span>
          <span>12:48</span>
        </div>
      </div>
      <div className="tl-memory-card tl-layer">
        <div className="tl-memory-switch" role="group" aria-label="Appointment preview view">
          {['Transcript', 'Summary'].map((item) => (
            <button key={item} aria-pressed={view === item} onClick={() => setView(item)}>
              {item}
            </button>
          ))}
        </div>
        <div className="tl-memory-content" aria-live="polite">
          {view === 'Summary' ? (
            <>
              <h3>Leave with something to return to.</h3>
              <p>You reviewed your notes and brought your questions to the appointment.</p>
              <div className="tl-next-step">
                <Check size={17} />
                <span>Keep your questions and follow-up notes together.</span>
              </div>
              <small>AI summaries stay separate from your own notes.</small>
            </>
          ) : (
            <>
              <div className="tl-transcript-line">
                <time>00:12</time>
                <p>“Let’s review what changed since your last visit.”</p>
              </div>
              <div className="tl-transcript-line">
                <time>00:18</time>
                <p>“I brought my notes and questions.”</p>
              </div>
              <div className="tl-transcript-line">
                <time>00:24</time>
                <p>“Great. Let’s go through them together.”</p>
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  );
}

// MARK: - Original entry followed by three chapters and a direct handoff to the working demo
export function TestLanding() {
  const [motionPaused, setMotionPaused] = useState(false);
  return (
    <div className={`tl-page${motionPaused ? ' tl-motion-paused' : ''}`}>
      <Landing />
      <div className="tl-tour-entry">
        <a className="tl-scroll-cue" href="#tour-records">
          <span>See how it comes together</span>
          <ArrowDown size={17} />
        </a>
        <button
          type="button"
          className="tl-motion-toggle"
          onClick={() => setMotionPaused((paused) => !paused)}
        >
          {motionPaused ? <Play size={13} /> : <Pause size={13} />}
          {motionPaused ? 'Resume motion' : 'Pause motion'}
        </button>
      </div>
      <div className="tl-tour" id="reva-in-motion">
        <section id="tour-records" className="tl-scene tl-records" aria-labelledby="tour-records-heading">
          <div className="tl-scene-inner">
            <div className="tl-copy">
              <h2 id="tour-records-heading">
                All the pieces.
                <br />
                <em>One place.</em>
              </h2>
              <p>
                The PDF in your inbox. The note on your phone. Bring your records together and find what
                matters when you need it.
              </p>
              <a className="tl-text-link" href="/demo#/records">
                Explore your records <ArrowUpRight size={17} />
              </a>
            </div>
            <RecordsPreview />
          </div>
        </section>
        <section
          id="tour-preparation"
          className="tl-scene tl-preparation"
          aria-labelledby="tour-preparation-heading"
        >
          <div className="tl-scene-inner">
            <div className="tl-copy">
              <h2 id="tour-preparation-heading">
                Walk in with
                <br />
                <em>a little clarity.</em>
              </h2>
              <p>
                Your history, the questions on your mind, and a brief that points back to your own records.
                Ready for a better conversation.
              </p>
              <a className="tl-text-link" href="/demo#/visits">
                Prepare for a visit <ArrowUpRight size={17} />
              </a>
            </div>
            <BriefPreview />
          </div>
        </section>
        <section id="tour-memory" className="tl-scene tl-memory" aria-labelledby="tour-memory-heading">
          <div className="tl-scene-inner">
            <div className="tl-copy">
              <h2 id="tour-memory-heading">
                Be there.
                <br />
                <em>Come back to it.</em>
              </h2>
              <p>
                Record the conversation, read the transcript, and revisit a concise summary. More room to
                listen. Less to hold in your head.
              </p>
              <a className="tl-text-link" href="/demo#/visits">
                Explore appointment notes <ArrowUpRight size={17} />
              </a>
              <p className="tl-consent">
                Get your doctor’s consent and permission from everyone present before recording. Review AI
                output against the original.
              </p>
            </div>
            <MemoryPreview />
          </div>
        </section>
      </div>
      <section className="tl-finish" aria-labelledby="tour-finish-heading">
        <Brand compact />
        <h2 id="tour-finish-heading">
          Your health.
          <br />A little more in hand.
        </h2>
        <p>Take a look around. Make it yours when you’re ready.</p>
        <div>
          <a className="button button-primary" href="/signup">
            Create your account
          </a>
          <a className="tl-text-link" href="/demo">
            Step inside the demo <ArrowUpRight size={18} />
          </a>
        </div>
        <small>Illustrative previews with fictional content. Explore the demo to try the app.</small>
      </section>
    </div>
  );
}
