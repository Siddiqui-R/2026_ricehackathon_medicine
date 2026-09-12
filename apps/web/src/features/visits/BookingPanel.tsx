// Purpose: Separate scheduling demonstrations from explicitly authorized connected clinic calls.
// Inputs: A visit, persisted booking requests, provider capability flags, and reviewed user details.
// Outputs: Saved simulation outcomes or durable live-call requests and manually refreshed transcripts.
// Side effects: Simulation mutates local state; a final live confirmation can invoke the configured call API.

import { useRef, useState, type FormEvent } from 'react';
import { Phone, RefreshCw } from 'lucide-react';
import { useReva } from '../../core/RevaContext';
import type { BookingRequest, Visit } from '../../core/models';
import { formatDate, nowISO, uid, validateBooking, confirmBooking } from '../../core/domain';
import { Badge, Button, Card, Field, Modal } from '../../components/ui';
import { dateFieldISO, dateFieldValue } from './visitDates';

// MARK: - Persisted request status and explicit actions
export function BookingPanel({ visit }: { visit: Visit }) {
  const { snapshot, providers, mutate, refreshCall, busy, reportError } = useReva();
  const [mode, setMode] = useState<'simulation' | 'live' | null>(null);
  const requests = (snapshot?.bookings ?? [])
    .filter((item) => item.visitID === visit.id)
    .slice()
    .reverse();
  const enabled = Boolean(providers?.booking.configured && providers.liveCallsEnabled);
  async function confirm(id: string) {
    try {
      await mutate((draft) => confirmBooking(id, draft));
    } catch (failure) {
      reportError(failure);
    }
  }
  return (
    <Card className="stack booking-panel">
      <div className="section-heading">
        <div>
          <h2>Appointment booking</h2>
          <p className="muted small">Review scheduling details and keep the outcome with this visit.</p>
        </div>
        <Phone size={21} />
      </div>
      <div className="row">
        <Button variant="secondary" onClick={() => setMode('simulation')}>
          Try booking demo
        </Button>
        {enabled && <Button onClick={() => setMode('live')}>Call clinic</Button>}
      </div>
      {!enabled && (
        <p className="muted small">
          Real calling becomes available after the calling service is configured and checked in{' '}
          <a className="text-link" href="#/settings">
            Settings
          </a>
          .
        </p>
      )}
      {requests.map((request) => (
        <div className="booking-request stack" key={request.id}>
          <div className="row">
            <Badge tone={request.isLive ? 'accent' : 'review'}>
              {request.isLive ? 'Real call' : 'Simulation'}
            </Badge>
            <strong>{bookingStatus(request.status)}</strong>
          </div>
          <div>
            <strong>{request.clinic}</strong>
            <p className="small muted">
              {request.phone} · {formatDate(request.earliest, true, request.timeZone)}
            </p>
          </div>
          {request.isLive ? (
            <>
              <p className="small">
                {request.status === 'unknown'
                  ? 'The call outcome is uncertain. Check this existing request and review the provider outcome before making any new call.'
                  : 'Call completion does not confirm an appointment. Review the outcome and edit this visit if the clinic confirmed a time.'}
              </p>
              <Button
                variant="secondary"
                onClick={() => {
                  void refreshCall(request.id).catch(() => {});
                }}
                disabled={busy}
              >
                <RefreshCw size={15} /> Check status
              </Button>
              {request.providerTranscript && (
                <details>
                  <summary>Review call transcript</summary>
                  <p className="prose small">{request.providerTranscript}</p>
                </details>
              )}
            </>
          ) : (
            <>
              <p className="small muted">
                {request.status === 'proposed'
                  ? `Demo time available: ${formatDate(request.earliest, true, request.timeZone)}. No clinic was contacted.`
                  : request.status === 'confirmed'
                    ? 'The simulated time was saved to this visit. No real appointment was booked.'
                    : request.status === 'needsUser'
                      ? 'The simulated clinic needs more details. You can try another demo request.'
                      : request.status === 'failed'
                        ? 'The simulated clinic did not answer. You can try another demo request.'
                        : 'This demonstration stays local and never contacts a clinic.'}
              </p>
              {request.status === 'proposed' && !request.confirmedVisitID && (
                <Button
                  variant="secondary"
                  onClick={() => {
                    void confirm(request.id);
                  }}
                  disabled={busy}
                >
                  Use simulated time
                </Button>
              )}
            </>
          )}
        </div>
      ))}
      {mode && <BookingEditor visit={visit} mode={mode} onClose={() => setMode(null)} />}
    </Card>
  );
}

function bookingStatus(status: string) {
  return (
    (
      {
        draft: 'Draft',
        queued: 'Queued',
        calling: 'Calling',
        proposed: 'Time available',
        needsUser: 'More details needed',
        failed: 'No answer',
        confirmed: 'Time saved',
        starting: 'Starting call',
        initiated: 'Call requested',
        'in-progress': 'In progress',
        done: 'Call ended',
        unknown: 'Outcome uncertain',
      } as Record<string, string>
    )[status] ?? status
  );
}

// MARK: - Review first; live consent is collected on a distinct final step
function BookingEditor({
  visit,
  mode,
  onClose,
}: {
  visit: Visit;
  mode: 'simulation' | 'live';
  onClose: () => void;
}) {
  const { snapshot, providers, mutate, startCall, busy } = useReva();
  const current = useRef({ snapshot, providers, busy });
  current.current = { snapshot, providers, busy };
  const inFlight = useRef(false);
  const [id] = useState(uid);
  const [clinic, setClinic] = useState(visit.clinic);
  const [phone, setPhone] = useState(mode === 'simulation' ? '+12025550100' : '');
  const [reason, setReason] = useState(visit.concern);
  const [earliest, setEarliest] = useState(dateFieldValue(visit.date, visit.timeZone));
  const [latest, setLatest] = useState(
    dateFieldValue(new Date(new Date(visit.date).getTime() + 7 * 86400000).toISOString(), visit.timeZone),
  );
  const [preferences, setPreferences] = useState('');
  const [scenario, setScenario] = useState('Appointment available');
  const [review, setReview] = useState<BookingRequest | null>(null);
  const [consent, setConsent] = useState(false);
  const submitted = Boolean(snapshot?.bookings.some((request) => request.id === id));
  const [reviewedPatient, setReviewedPatient] = useState('');
  const [working, setWorking] = useState(false);
  const [error, setError] = useState('');
  function reviewRequest(event: FormEvent) {
    event.preventDefault();
    setError('');
    try {
      const request: BookingRequest = {
        id,
        visitID: visit.id,
        clinic: clinic.trim(),
        phone: phone.trim(),
        reason: reason.trim(),
        earliest: dateFieldISO(earliest, visit.timeZone),
        latest: dateFieldISO(latest, visit.timeZone),
        timeZone: visit.timeZone,
        preferences: preferences.trim(),
        status: 'draft',
        scenario,
        createdAt: nowISO(),
        isLive: mode === 'live',
      };
      validateBooking(request);
      if (mode === 'live' && !/^\+[1-9]\d{9,14}$/.test(request.phone))
        throw new Error('Use the full clinic phone number, beginning with + and the country code.');
      setReview(request);
      setReviewedPatient(current.current.snapshot?.profile.name ?? '');
      setConsent(false);
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : 'Check the booking details.');
    }
  }
  async function submit() {
    if (
      !review ||
      inFlight.current ||
      current.current.snapshot?.bookings.some((request) => request.id === id) ||
      (mode === 'live' && !consent)
    )
      return;
    inFlight.current = true;
    setWorking(true);
    setError('');
    try {
      if (mode === 'live') {
        if (current.current.busy)
          throw new Error('Wait for the other connected action to finish, then review this call again.');
        if (!current.current.providers?.booking.configured || !current.current.providers.liveCallsEnabled)
          throw new Error('The live calling service is no longer enabled. Check Settings before continuing.');
        if (current.current.snapshot?.profile.name !== reviewedPatient)
          throw new Error(
            'The patient name changed. Edit the details and review the call again before authorizing it.',
          );
        await startCall(review);
      } else {
        await mutate((draft) => {
          if (!draft.bookings.some((item) => item.id === id))
            draft.bookings.push({ ...review, status: 'queued' });
        });
        await new Promise((resolve) => setTimeout(resolve, 400));
        await mutate((draft) => {
          const item = draft.bookings.find((item) => item.id === id);
          if (item?.status === 'queued' && !item.isLive) item.status = 'calling';
        });
        await new Promise((resolve) => setTimeout(resolve, 650));
        await mutate((draft) => {
          const item = draft.bookings.find((item) => item.id === id);
          if (item?.status === 'calling' && !item.isLive)
            item.status =
              review.scenario === 'Clinic needs details'
                ? 'needsUser'
                : review.scenario === 'No answer'
                  ? 'failed'
                  : 'proposed';
        });
      }
      onClose();
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : 'The request could not be completed.');
    } finally {
      inFlight.current = false;
      setWorking(false);
    }
  }

  // MARK: - Scheduling form and immutable final review
  return (
    <Modal
      title={mode === 'live' ? 'Call your clinic' : 'Try appointment booking'}
      onClose={() => {
        if (!working) onClose();
      }}
    >
      {review ? (
        <div className="stack">
          <Badge tone={mode === 'live' ? 'accent' : 'review'}>
            {mode === 'live' ? 'Real outbound call' : 'Local demonstration'}
          </Badge>
          <h3>Review every detail</h3>
          <dl className="review-details">
            <dt>Clinic</dt>
            <dd>{review.clinic}</dd>
            <dt>Phone</dt>
            <dd>{review.phone}</dd>
            <dt>Patient</dt>
            <dd>{reviewedPatient}</dd>
            <dt>Reason</dt>
            <dd className="prose">{review.reason}</dd>
            <dt>Allowed window</dt>
            <dd>
              {formatDate(review.earliest, true, review.timeZone)} –{' '}
              {formatDate(review.latest, true, review.timeZone)}
              <br />
              {review.timeZone}
            </dd>
            <dt>Preferences</dt>
            <dd>{review.preferences || 'None entered'}</dd>
          </dl>
          {mode === 'live' ? (
            <>
              <p className="small">
                The connected calling service receives your name, clinic number, reason, scheduling window,
                and preferences. Reva will keep this request’s identity and will not automatically redial an
                uncertain call.
              </p>
              <label className="row">
                <input
                  type="checkbox"
                  checked={consent}
                  disabled={working || submitted}
                  onChange={(event) => setConsent(event.target.checked)}
                />
                <span>I authorize this real call and sharing the reviewed details.</span>
              </label>
            </>
          ) : (
            <p>No call is made. The selected demo outcome is “{review.scenario}.”</p>
          )}
          {mode === 'live' && busy && !working && !submitted && (
            <p className="small" role="status">
              Wait for the other connected action to finish before placing this call.
            </p>
          )}
          {error && (
            <p className="inline-error" role="alert">
              {error}
            </p>
          )}
          {submitted && !working && (
            <p className="small">
              This request is saved. Close this dialog and check its status before taking further action; a
              saved call attempt can have an uncertain outcome.
            </p>
          )}
          <div className="form-actions">
            <Button
              variant="secondary"
              disabled={working}
              onClick={() => (submitted ? onClose() : setReview(null))}
            >
              {submitted ? 'Close' : 'Edit details'}
            </Button>
            <Button
              disabled={working || submitted || (mode === 'live' && (!consent || busy))}
              onClick={() => {
                void submit();
              }}
            >
              {working ? 'Submitting…' : mode === 'live' ? 'Place real call' : 'Run simulation'}
            </Button>
          </div>
        </div>
      ) : (
        <form className="stack" onSubmit={reviewRequest}>
          <p className="muted">
            {mode === 'live'
              ? 'You will review and authorize the call before anything is sent.'
              : 'Explore the booking flow with a fictional outcome. This never contacts a clinic.'}
          </p>
          <Field label="Clinic">
            <input
              required
              maxLength={180}
              value={clinic}
              onChange={(event) => setClinic(event.target.value)}
            />
          </Field>
          <Field label="Clinic phone" hint="Include + and the country code, e.g. +12025550100.">
            <input
              required
              type="tel"
              maxLength={24}
              value={phone}
              onChange={(event) => setPhone(event.target.value)}
            />
          </Field>
          <Field label="Reason shared with the clinic">
            <textarea
              required
              rows={3}
              maxLength={4000}
              value={reason}
              onChange={(event) => setReason(event.target.value)}
            />
          </Field>
          <div className="form-grid">
            <Field label="Earliest time">
              <input
                required
                type="datetime-local"
                value={earliest}
                onChange={(event) => setEarliest(event.target.value)}
              />
            </Field>
            <Field label="Latest time">
              <input
                required
                type="datetime-local"
                min={earliest}
                value={latest}
                onChange={(event) => setLatest(event.target.value)}
              />
            </Field>
          </div>
          <p className="muted small">Times are entered in {visit.timeZone}.</p>
          <Field label="Scheduling preferences">
            <textarea
              rows={2}
              maxLength={4000}
              value={preferences}
              onChange={(event) => setPreferences(event.target.value)}
            />
          </Field>
          {mode === 'simulation' && (
            <Field label="Demo outcome">
              <select value={scenario} onChange={(event) => setScenario(event.target.value)}>
                {['Appointment available', 'Clinic needs details', 'No answer'].map((value) => (
                  <option key={value}>{value}</option>
                ))}
              </select>
            </Field>
          )}
          {error && (
            <p className="inline-error" role="alert">
              {error}
            </p>
          )}
          <div className="form-actions">
            <Button type="button" variant="secondary" onClick={onClose}>
              Cancel
            </Button>
            <Button type="submit">Review details</Button>
          </div>
        </form>
      )}
    </Modal>
  );
}
