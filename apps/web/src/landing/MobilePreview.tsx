// A real, interactive demo in a phone-sized viewport; shared app code stays current automatically.
import { useEffect, useState } from 'react';
import { ArrowUpRight } from 'lucide-react';
import { Brand } from '../components/Brand';
import { selectedDemoPerson } from '../core/demoProfiles';
import '../styles/mobile-preview.css';

export function MobilePreview() {
  const [source] = useState(() => {
    const url = new URL('/demo', location.origin);
    url.searchParams.set('demo', selectedDemoPerson());
    url.hash = location.hash.startsWith('#/') ? location.hash : '/summary';
    return url.pathname + url.search + url.hash;
  });
  useEffect(() => { document.title = 'Mobile preview · Reva'; }, []);
  return (
    <div className="mobile-preview">
      <header className="mobile-preview-header">
        <a href="/" aria-label="Reva home"><Brand /></a>
        <div className="mobile-preview-heading">
          <h1>Mobile preview</h1>
          <p>Explore the interactive demo at phone size.</p>
        </div>
        <a href={source} className="mobile-preview-open">
          Open full screen <ArrowUpRight size={16} aria-hidden="true" />
        </a>
      </header>
      <main className="mobile-preview-stage">
        <div className="mobile-preview-phone">
          <iframe title="Reva mobile demo" src={source} allow="camera; microphone" />
        </div>
      </main>
    </div>
  );
}
