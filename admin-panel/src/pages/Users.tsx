import { useState } from 'react';

import { ErrorBox, Modal, Pager, StatusBadge, useAction, useData, useDebounced } from '../components/ui';
import { api } from '../lib/api';
import { formatDate, formatDateTime, initials } from '../lib/format';
import type { AdminUser, Page, UserDetail } from '../lib/types';

const STATUSES = [
  ['all', 'All users'], ['active', 'Active'], ['incomplete', 'Profile incomplete'],
  ['suspended', 'Suspended'], ['banned', 'Banned'], ['deactivated', 'Deactivated'],
] as const;
const PAGE_SIZE = 20;

type Dialog =
  | { kind: 'view'; user: AdminUser }
  | { kind: 'suspend'; user: AdminUser }
  | { kind: 'ban'; user: AdminUser }
  | { kind: 'delete'; user: AdminUser }
  | null;

function Avatar({ user }: { user: AdminUser }) {
  const src = user.avatar_url || user.photo_url;
  return <div className="avatar">{src ? <img src={src} alt="" loading="lazy" /> : initials(user.full_name, user.email)}</div>;
}

function UserDetails({ user }: { user: AdminUser }) {
  const { data, error } = useData(() => api<UserDetail>(`/admin/users/${user.id}`), [user.id]);
  const p = data?.profile;
  const fields: [string, unknown][] = p ? [
    ['Email', p.email], ['Username', p.username], ['Gender', p.gender], ['Joined', formatDate(p.created_at)],
    ['Height', p.height_cm ? `${p.height_cm} cm` : null], ['Weight', p.weight_kg ? `${p.weight_kg} kg` : null],
    ['Chest / waist / hip', [p.chest_cm, p.waist_cm, p.hip_cm].some(Boolean) ? `${p.chest_cm ?? '—'} / ${p.waist_cm ?? '—'} / ${p.hip_cm ?? '—'} cm` : null],
    ['Skin tone', p.skin_tone], ['Body type', p.body_type],
    ['Suspended until', p.suspended_until ? formatDateTime(p.suspended_until) : null], ['Suspension reason', p.suspension_reason],
    ['Ban reason', p.ban_reason], ['Deactivated', p.deactivated_at ? formatDateTime(p.deactivated_at) : null],
  ] : [];
  return (
    <>
      <div className="row">
        <Avatar user={user} />
        <div>
          <div style={{ fontWeight: 700 }}>{user.full_name || 'Unnamed user'}</div>
          <StatusBadge status={user.status} />
        </div>
      </div>
      {error && <ErrorBox message={error} />}
      {data && (
        <>
          <dl className="drawer-grid">
            <div><dt>Chat sessions</dt><dd>{data.counts.chat_sessions}</dd></div>
            <div><dt>Saved items</dt><dd>{data.counts.saved_items}</dd></div>
            <div><dt>Feedback given</dt><dd>{data.counts.feedback}</dd></div>
          </dl>
          <dl className="drawer-grid">
            {fields.filter(([, v]) => v !== null && v !== undefined && v !== '').map(([k, v]) => (
              <div key={k}><dt>{k}</dt><dd>{String(v)}</dd></div>
            ))}
          </dl>
        </>
      )}
    </>
  );
}

export function Users() {
  const [search, setSearch] = useState('');
  const [status, setStatus] = useState<string>('all');
  const [page, setPage] = useState(1);
  const [dialog, setDialog] = useState<Dialog>(null);
  const [days, setDays] = useState(7);
  const [reason, setReason] = useState('');
  const [confirm, setConfirm] = useState('');
  const term = useDebounced(search);
  const { data, error, loading, reload } = useData(
    () => api<Page<AdminUser>>('/admin/users', { query: { search: term, status, page, page_size: PAGE_SIZE } }),
    [term, status, page],
  );
  const { busy, run } = useAction();

  const open = (d: Dialog) => { setReason(''); setConfirm(''); setDays(7); setDialog(d); };
  const close = () => setDialog(null);
  const act = async (fn: () => Promise<unknown>, msg: string) => {
    if (await run(fn, msg)) { close(); reload(); }
  };

  return (
    <>
      <div className="page-head">
        <div><h1>Users</h1><p>View, search, suspend, ban or permanently remove accounts.</p></div>
      </div>
      <div className="row" style={{ marginBottom: 14 }}>
        <input className="input search" type="search" placeholder="Search name, username or email" value={search}
          onChange={(e) => { setSearch(e.target.value); setPage(1); }} aria-label="Search users" />
        <select className="select" value={status} onChange={(e) => { setStatus(e.target.value); setPage(1); }} aria-label="Status">
          {STATUSES.map(([v, l]) => <option key={v} value={v}>{l}</option>)}
        </select>
      </div>
      {error && <ErrorBox message={error} onRetry={reload} />}
      <div className={`table-wrap${loading && data ? ' loading' : ''}`}>
        <table>
          <thead><tr><th>User</th><th>Status</th><th>Gender</th><th>Joined</th><th style={{ textAlign: 'right' }}>Actions</th></tr></thead>
          <tbody>
            {data?.items.map((u) => (
              <tr key={u.id}>
                <td>
                  <div className="cell-user">
                    <Avatar user={u} />
                    <div style={{ minWidth: 0 }}>
                      <div style={{ fontWeight: 600 }}>{u.full_name || 'Unnamed user'}</div>
                      <div className="small muted">{u.email}</div>
                    </div>
                  </div>
                </td>
                <td><StatusBadge status={u.status} /></td>
                <td>{u.gender ?? '—'}</td>
                <td>{formatDate(u.created_at)}</td>
                <td>
                  <div className="actions">
                    <button className="btn btn-sm" onClick={() => open({ kind: 'view', user: u })}>View</button>
                    {u.status === 'suspended'
                      ? <button className="btn btn-sm" disabled={busy} onClick={() => act(() => api(`/admin/users/${u.id}/unsuspend`, { method: 'POST' }), 'Suspension lifted.')}>Lift suspension</button>
                      : u.status !== 'banned' && <button className="btn btn-sm" onClick={() => open({ kind: 'suspend', user: u })}>Suspend</button>}
                    {u.status === 'banned'
                      ? <button className="btn btn-sm" disabled={busy} onClick={() => act(() => api(`/admin/users/${u.id}/unban`, { method: 'POST' }), 'Ban lifted.')}>Unban</button>
                      : <button className="btn btn-sm" onClick={() => open({ kind: 'ban', user: u })}>Ban</button>}
                    <button className="btn btn-sm btn-danger" onClick={() => open({ kind: 'delete', user: u })}>Delete</button>
                  </div>
                </td>
              </tr>
            ))}
            {data && data.items.length === 0 && <tr><td colSpan={5} className="empty">No users match.</td></tr>}
            {!data && loading && <tr><td colSpan={5} className="empty">Loading…</td></tr>}
          </tbody>
        </table>
      </div>
      {data && <Pager page={page} pageSize={PAGE_SIZE} total={data.total} onPage={setPage} />}

      {dialog?.kind === 'view' && (
        <Modal title="User details" onClose={close} wide footer={<button className="btn" onClick={close}>Close</button>}>
          <UserDetails user={dialog.user} />
        </Modal>
      )}
      {dialog?.kind === 'suspend' && (
        <Modal title={`Suspend ${dialog.user.full_name || dialog.user.email}`} onClose={close} footer={<>
          <button className="btn" onClick={close}>Cancel</button>
          <button className="btn btn-primary" disabled={busy} onClick={() => act(
            () => api(`/admin/users/${dialog.user.id}/suspend`, { method: 'POST', body: { days, reason } }), 'User suspended.')}>Suspend</button>
        </>}>
          <div className="stack">
            <p className="muted" style={{ margin: 0 }}>They can't use the app until the suspension ends; they see the reason when they sign in.</p>
            <div className="field">
              <label htmlFor="days">Length</label>
              <select id="days" className="select" value={days} onChange={(e) => setDays(Number(e.target.value))}>
                {[1, 3, 7, 14, 30, 90].map((d) => <option key={d} value={d}>{d} {d === 1 ? 'day' : 'days'}</option>)}
              </select>
            </div>
            <div className="field">
              <label htmlFor="reason">Reason</label>
              <textarea id="reason" className="textarea" value={reason} maxLength={500} onChange={(e) => setReason(e.target.value)}
                placeholder="e.g. Repeated inappropriate messages" />
            </div>
          </div>
        </Modal>
      )}
      {dialog?.kind === 'ban' && (
        <Modal title={`Ban ${dialog.user.full_name || dialog.user.email}`} onClose={close} footer={<>
          <button className="btn" onClick={close}>Cancel</button>
          <button className="btn btn-danger" disabled={busy} onClick={() => act(
            () => api(`/admin/users/${dialog.user.id}/ban`, { method: 'POST', body: { reason } }), 'User banned.')}>Ban user</button>
        </>}>
          <div className="stack">
            <p className="muted" style={{ margin: 0 }}>A ban blocks the account until you lift it. Nothing is deleted.</p>
            <div className="field">
              <label htmlFor="banreason">Reason</label>
              <textarea id="banreason" className="textarea" value={reason} maxLength={500} onChange={(e) => setReason(e.target.value)} />
            </div>
          </div>
        </Modal>
      )}
      {dialog?.kind === 'delete' && (
        <Modal title="Permanently delete account" onClose={close} footer={<>
          <button className="btn" onClick={close}>Cancel</button>
          <button className="btn btn-danger" disabled={busy || confirm !== 'DELETE'} onClick={() => act(
            () => api(`/admin/users/${dialog.user.id}`, { method: 'DELETE' }), 'Account deleted.')}>Delete forever</button>
        </>}>
          <div className="stack">
            <div className="alert">
              This removes {dialog.user.email}'s account, profile, photos, chats, wardrobe and feedback. It cannot be undone.
            </div>
            <div className="field">
              <label htmlFor="confirm">Type DELETE to confirm</label>
              <input id="confirm" className="input" value={confirm} onChange={(e) => setConfirm(e.target.value)} autoComplete="off" />
            </div>
          </div>
        </Modal>
      )}
    </>
  );
}
