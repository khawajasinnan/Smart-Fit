import { useState, type ChangeEvent } from 'react';

import { api } from '../lib/api';
import { splitList } from '../lib/format';
import type { Product } from '../lib/types';
import { Modal, useAction } from './ui';

interface FormState {
  retailer: 'outfitters' | 'breakout';
  product_url: string;
  name: string;
  image_url: string;
  extra_image_urls: string;
  price: string;
  sizes_in_stock: string;
  all_sizes: string;
  category: string;
  tryon_category: 'upper' | 'lower' | 'dress';
  gender: 'men' | 'women' | 'unisex';
  colors: string;
}

function fromProduct(p?: Product): FormState {
  return {
    retailer: p?.retailer ?? 'breakout',
    product_url: p?.product_url ?? '',
    name: p?.name ?? '',
    image_url: p?.image_url ?? '',
    extra_image_urls: '',
    price: p ? String(p.price) : '',
    sizes_in_stock: p?.sizes.join(', ') ?? '',
    all_sizes: p?.all_sizes.join(', ') ?? '',
    category: p?.category ?? '',
    tryon_category: p?.tryon_category ?? 'upper',
    gender: p?.gender ?? 'women',
    colors: p?.colors.join(', ') ?? '',
  };
}

/** Add (no product) or edit (product given). The backend validates hosts,
 * price and categories and returns a readable reason when something is off. */
export function ProductDialog({ product, onClose, onSaved }: { product?: Product; onClose: () => void; onSaved: () => void }) {
  const [f, setF] = useState<FormState>(() => fromProduct(product));
  const { busy, run } = useAction();
  const set = (k: keyof FormState) => (e: ChangeEvent<HTMLInputElement | HTMLSelectElement>) => setF({ ...f, [k]: e.target.value });

  const save = async () => {
    const fields = {
      name: f.name.trim(), image_url: f.image_url.trim(), price: Number(f.price),
      sizes_in_stock: splitList(f.sizes_in_stock), all_sizes: splitList(f.all_sizes), category: f.category.trim(),
      tryon_category: f.tryon_category, gender: f.gender, colors: splitList(f.colors),
      ...(f.extra_image_urls.trim() ? { extra_image_urls: splitList(f.extra_image_urls) } : {}),
    };
    const ok = product
      ? await run(() => api(`/admin/products/${encodeURIComponent(product.product_id)}`, { method: 'PATCH', body: fields }), 'Product updated.')
      : await run(() => api('/admin/products', { method: 'POST', body: { ...fields, retailer: f.retailer, product_url: f.product_url.trim() } }), 'Product added.');
    if (ok) { onSaved(); onClose(); }
  };

  return (
    <Modal title={product ? 'Edit product' : 'Add product'} onClose={onClose} wide footer={<>
      <button className="btn" onClick={onClose}>Cancel</button>
      <button className="btn btn-primary" disabled={busy || !f.name || !f.price || !f.image_url || (!product && !f.product_url)} onClick={save}>
        {product ? 'Save changes' : 'Add product'}
      </button>
    </>}>
      <div className="grid grid-2" style={{ gap: 14 }}>
        <div className="field">
          <label htmlFor="retailer">Retailer</label>
          <select id="retailer" className="select" value={f.retailer} onChange={set('retailer')} disabled={!!product}>
            <option value="breakout">Breakout</option>
            <option value="outfitters">Outfitters</option>
          </select>
        </div>
        <div className="field">
          <label htmlFor="url">Product page URL</label>
          <input id="url" className="input" value={f.product_url} onChange={set('product_url')} disabled={!!product}
            placeholder="https://www.breakout.com.pk/products/…" />
          {product && <span className="hint">The URL is the product's id and can't change.</span>}
        </div>
        <div className="field"><label htmlFor="name">Name</label><input id="name" className="input" value={f.name} onChange={set('name')} /></div>
        <div className="field"><label htmlFor="price">Price (PKR)</label><input id="price" className="input" type="number" min="1" value={f.price} onChange={set('price')} /></div>
        <div className="field" style={{ gridColumn: '1 / -1' }}>
          <label htmlFor="img">Main image URL</label>
          <input id="img" className="input" value={f.image_url} onChange={set('image_url')} placeholder="https://cdn.shopify.com/…" />
          <span className="hint">Full-size image (no crop/width/height parameters).</span>
        </div>
        {!product && (
          <div className="field" style={{ gridColumn: '1 / -1' }}>
            <label htmlFor="extra">More image URLs (optional)</label>
            <input id="extra" className="input" value={f.extra_image_urls} onChange={set('extra_image_urls')} placeholder="Comma-separated" />
          </div>
        )}
        <div className="field"><label htmlFor="sizes">Sizes in stock</label><input id="sizes" className="input" value={f.sizes_in_stock} onChange={set('sizes_in_stock')} placeholder="S, M, L" /></div>
        <div className="field"><label htmlFor="allsizes">All sizes</label><input id="allsizes" className="input" value={f.all_sizes} onChange={set('all_sizes')} placeholder="XS, S, M, L, XL" /></div>
        <div className="field"><label htmlFor="cat">Category</label><input id="cat" className="input" value={f.category} onChange={set('category')} placeholder="t-shirts" /></div>
        <div className="field"><label htmlFor="colors">Colours</label><input id="colors" className="input" value={f.colors} onChange={set('colors')} placeholder="Black, White" /></div>
        <div className="field">
          <label htmlFor="slot">Try-on slot</label>
          <select id="slot" className="select" value={f.tryon_category} onChange={set('tryon_category')}>
            <option value="upper">Upper body</option><option value="lower">Lower body</option><option value="dress">Dress</option>
          </select>
        </div>
        <div className="field">
          <label htmlFor="gender">Gender</label>
          <select id="gender" className="select" value={f.gender} onChange={set('gender')}>
            <option value="women">Women</option><option value="men">Men</option><option value="unisex">Unisex</option>
          </select>
        </div>
      </div>
    </Modal>
  );
}

/** Breakout catalog from a CSV file (template: backend/services/scraper/templates). */
export function ImportCsvDialog({ onClose, onDone }: { onClose: () => void; onDone: () => void }) {
  const [text, setText] = useState('');
  const [fileName, setFileName] = useState('');
  const [result, setResult] = useState<{ stored: number; problems: string[] } | null>(null);
  const { busy, run } = useAction();

  const pick = async (e: ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    setResult(null);
    if (!file) return;
    setFileName(file.name);
    setText(await file.text());
  };

  const upload = () => run(async () => {
    const r = await api<{ stored: number; problems: string[] }>('/admin/catalog/import-csv', {
      method: 'POST', body: { retailer: 'breakout', csv_text: text },
    });
    setResult(r);
    onDone();
  }, 'CSV imported.');

  return (
    <Modal title="Import Breakout CSV" onClose={onClose} footer={<>
      <button className="btn" onClick={onClose}>{result ? 'Done' : 'Cancel'}</button>
      {!result && <button className="btn btn-primary" disabled={busy || !text} onClick={upload}>Import</button>}
    </>}>
      <div className="stack">
        <p className="muted" style={{ margin: 0 }}>
          Columns: name, product_url, image_url, extra_image_urls, price, sizes_in_stock, all_sizes, category,
          tryon_category, gender, colors. Lists use "|". Existing products are updated.
        </p>
        <input type="file" accept=".csv,text/csv" onChange={pick} aria-label="CSV file" />
        {fileName && <span className="small muted">{fileName} · {text.split('\n').filter(Boolean).length - 1} rows</span>}
        {result && (
          <div className={result.problems.length ? 'alert' : 'alert info'}>
            {result.stored} products imported.
            {result.problems.length > 0 && (
              <ul style={{ margin: '8px 0 0', paddingLeft: 18 }}>{result.problems.slice(0, 20).map((p) => <li key={p}>{p}</li>)}</ul>
            )}
          </div>
        )}
      </div>
    </Modal>
  );
}
