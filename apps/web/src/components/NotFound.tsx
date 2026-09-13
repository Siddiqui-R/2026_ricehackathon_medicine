// Shared recovery message for unknown public and workspace routes.
import { useEffect } from 'react';
import '../styles/not-found.css';

export function NotFound() {
  useEffect(() => {
    document.title = 'Page not found · Reva';
  }, []);
  return (
    <div className="not-found-content">
      <p className="not-found-code">404</p>
      <h1>This page doesn’t exist.</h1>
      <p>The link may be incorrect or the page may have moved.</p>
      <a className="not-found-home" href="/">
        Back to home
      </a>
    </div>
  );
}
