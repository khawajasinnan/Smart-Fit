import { useState } from 'react';

import { ImportCsvDialog, ProductDialog } from '../components/CatalogDialogs';
import { ErrorBox, Modal, Pager, useAction, useData, useDebounced } from '../components/ui';
import { api } from '../lib/api';
import { formatPkr, timeAgo } from '../lib/format';
import type { Product, ProductPage } from '../lib/types';

const PAGE_SIZE = 20;
const SLOT: Record<string, string> = { upper: 'Upper', lower: 'Lower', dress: 'Dress' };

export function Catalog() {
  const [search, setSearch] = useState('');
  const [retailer, setRetailer] = useState('');
  const [slot, setSlot] = useState('');
  const [page, setPage] = useState(1);
  const [editing, setEditing] = useState<Product | 'new' | null>(null);
  const [deleting, setDeleting] = useState<Product | null>(null);
  const [importing, setImporting] = useState(false);
  const term = useDebounced(search);
  const { data, error, loading, reload } = useData(
    () => api<ProductPage>('/admin/products', { query: { search: term, retailer, tryon_category: slot, page, page_size: PAGE_SIZE } }),
    [term, retailer, slot, page],
  );
  const { busy, run } = useAction();

  const remove = async () => {
    if (!deleting) return;
    if (await run(() => api(`/admin/products/${encodeURIComponent(deleting.product_id)}`, { method: 'DELETE' }), 'Product removed.')) {
      setDeleting(null);
      reload();
    }
  };

  return (
    <>
      <div className="page-head">
        <div>
          <h1>Catalog</h1>
          <p>{data ? Object.entries(data.by_retailer).map(([r, n]) => `${n} ${r}`).join(' · ') : 'Fashion items users are recommended.'}</p>
        </div>
        <div className="row">
          <button className="btn" onClick={() => setImporting(true)}>Import CSV</button>
          <button className="btn btn-primary" onClick={() => setEditing('new')}>Add product</button>
        </div>
      </div>
      <div className="row" style={{ marginBottom: 14 }}>
        <input className="input search" type="search" placeholder="Search name, category or id" value={search}
          onChange={(e) => { setSearch(e.target.value); setPage(1); }} aria-label="Search products" />
        <select className="select" value={retailer} onChange={(e) => { setRetailer(e.target.value); setPage(1); }} aria-label="Retailer">
          <option value="">All retailers</option><option value="outfitters">Outfitters</option><option value="breakout">Breakout</option>
        </select>
        <select className="select" value={slot} onChange={(e) => { setSlot(e.target.value); setPage(1); }} aria-label="Try-on slot">
          <option value="">All slots</option><option value="upper">Upper</option><option value="lower">Lower</option><option value="dress">Dress</option>
        </select>
      </div>
      {error && <ErrorBox message={error} onRetry={reload} />}
      <div className={`table-wrap${loading && data ? ' loading' : ''}`}>
        <table>
          <thead><tr><th>Product</th><th>Retailer</th><th>Price</th><th>Sizes in stock</th><th>Type</th><th>Updated</th><th style={{ textAlign: 'right' }}>Actions</th></tr></thead>
          <tbody>
            {data?.items.map((p) => (
              <tr key={p.product_id}>
                <td>
                  <div className="cell-user">
                    <img className="thumb" src={p.image_url} alt="" loading="lazy" />
                    <div style={{ minWidth: 0 }}>
                      <a href={p.product_url} target="_blank" rel="noreferrer" style={{ fontWeight: 600, color: 'inherit' }}>{p.name}</a>
                      <div className="small muted">{p.product_id}{p.has_size_chart ? ' · size chart' : ''}</div>
                    </div>
                  </div>
                </td>
                <td style={{ textTransform: 'capitalize' }}>{p.retailer}</td>
                <td>{formatPkr(p.price)}</td>
                <td>{p.sizes.length ? p.sizes.join(', ') : <span className="badge badge-warn">Out of stock</span>}</td>
                <td>{SLOT[p.tryon_category]} · {p.gender}<div className="small muted">{p.category}</div></td>
                <td>{timeAgo(p.scraped_at)}<div className="small muted">{p.source.replace('_', ' ')}</div></td>
                <td>
                  <div className="actions">
                    <button className="btn btn-sm" onClick={() => setEditing(p)}>Edit</button>
                    <button className="btn btn-sm btn-danger" onClick={() => setDeleting(p)}>Remove</button>
                  </div>
                </td>
              </tr>
            ))}
            {data && data.items.length === 0 && <tr><td colSpan={7} className="empty">No products match.</td></tr>}
            {!data && loading && <tr><td colSpan={7} className="empty">Loading…</td></tr>}
          </tbody>
        </table>
      </div>
      {data && <Pager page={page} pageSize={PAGE_SIZE} total={data.total} onPage={setPage} />}

      {editing && <ProductDialog product={editing === 'new' ? undefined : editing} onClose={() => setEditing(null)} onSaved={reload} />}
      {importing && <ImportCsvDialog onClose={() => setImporting(false)} onDone={reload} />}
      {deleting && (
        <Modal title="Remove product" onClose={() => setDeleting(null)} footer={<>
          <button className="btn" onClick={() => setDeleting(null)}>Cancel</button>
          <button className="btn btn-danger" disabled={busy} onClick={remove}>Remove</button>
        </>}>
          <p style={{ margin: 0 }}>Remove <strong>{deleting.name}</strong> from the catalog?</p>
          {deleting.source === 'shopify_feed' && (
            <p className="muted">It comes from the retailer's feed and will return on the next refresh. To stop that, disable the retailer under Scraping.</p>
          )}
        </Modal>
      )}
    </>
  );
}
