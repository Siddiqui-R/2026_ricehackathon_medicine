// Purpose: Validate uploaded original audio and inspect its duration without sending it anywhere.
// Inputs: A user-selected audio File and browser metadata support.
// Outputs: A supported original, duration, filename and extension, or an actionable validation error.
// Side effects: Creates a short-lived local audio URL and releases it after bounded metadata inspection.

import { MAX_AUDIO_BYTES } from './useVisitRecorder';

export interface UploadedAudio {
  blob: File;
  duration: number;
  extension: string;
}

// MARK: - Validate before allocating a playback URL; always release media resources
export async function inspectAudio(file: File): Promise<UploadedAudio> {
  const extension = file.name.split('.').pop()?.toLowerCase() ?? '';
  if (!['m4a', 'mp4', 'mp3', 'wav', 'webm', 'ogg'].includes(extension))
    throw new Error('Choose an M4A, MP3, WAV, WebM, or Ogg audio file.');
  if (!file.size || file.size > MAX_AUDIO_BYTES)
    throw new Error('Audio must be nonempty and no larger than 16 MiB.');
  const url = URL.createObjectURL(file);
  const audio = document.createElement('audio');
  audio.preload = 'metadata';
  let timeout: number | undefined;
  try {
    const duration = await new Promise<number>((resolve, reject) => {
      timeout = window.setTimeout(
        () => reject(new Error('This audio could not be read. Try an MP3, M4A, or WAV file.')),
        10000,
      );
      audio.onloadedmetadata = () => {
        Number.isFinite(audio.duration) && audio.duration > 0 && audio.duration <= 24 * 3600
          ? resolve(audio.duration)
          : reject(
              new Error('This file has no usable duration. Export it as MP3, M4A, or WAV and try again.'),
            );
      };
      audio.onerror = () =>
        reject(new Error('The browser cannot read this audio file. Try MP3, M4A, or WAV.'));
      audio.src = url;
    });
    return { blob: file, duration, extension };
  } finally {
    window.clearTimeout(timeout);
    audio.onloadedmetadata = null;
    audio.onerror = null;
    audio.removeAttribute('src');
    audio.load();
    URL.revokeObjectURL(url);
  }
}
