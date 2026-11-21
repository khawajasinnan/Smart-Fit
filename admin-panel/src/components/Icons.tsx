const base = { fill: 'none', stroke: 'currentColor', strokeWidth: 2, strokeLinecap: 'round' as const, strokeLinejoin: 'round' as const, 'aria-hidden': true };

export const IconDashboard = () => (<svg viewBox="0 0 24 24" {...base}><rect x="3" y="3" width="7" height="9" rx="2" /><rect x="14" y="3" width="7" height="5" rx="2" /><rect x="14" y="12" width="7" height="9" rx="2" /><rect x="3" y="16" width="7" height="5" rx="2" /></svg>);
export const IconUsers = () => (<svg viewBox="0 0 24 24" {...base}><circle cx="9" cy="8" r="4" /><path d="M2 21a7 7 0 0 1 14 0" /><path d="M16 4a4 4 0 0 1 0 8M22 21a7 7 0 0 0-4-6.3" /></svg>);
export const IconShirt = () => (<svg viewBox="0 0 24 24" {...base}><path d="M8 3 3 6l2 5 3-1v11h8V10l3 1 2-5-5-3a4 4 0 0 1-8 0Z" /></svg>);
export const IconSpider = () => (<svg viewBox="0 0 24 24" {...base}><path d="M12 3v3M4 7l3 2M20 7l-3 2M4 17l3-2M20 17l-3-2" /><rect x="7" y="8" width="10" height="10" rx="5" /></svg>);
export const IconHeart = () => (<svg viewBox="0 0 24 24" {...base}><path d="M12 20s-7-4.4-9-9a5 5 0 0 1 9-3 5 5 0 0 1 9 3c-2 4.6-9 9-9 9Z" /></svg>);
export const IconFlag = () => (<svg viewBox="0 0 24 24" {...base}><path d="M5 21V4M5 4h11l-2 4 2 4H5" /></svg>);
export const IconPulse = () => (<svg viewBox="0 0 24 24" {...base}><path d="M3 12h4l3-8 4 16 3-8h4" /></svg>);
export const IconSun = () => (<svg viewBox="0 0 24 24" {...base}><circle cx="12" cy="12" r="4" /><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4" /></svg>);
export const IconMoon = () => (<svg viewBox="0 0 24 24" {...base}><path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5Z" /></svg>);
export const IconCheck = () => (<svg viewBox="0 0 24 24" {...base}><path d="m5 12 5 5L20 7" /></svg>);
export const IconAlert = () => (<svg viewBox="0 0 24 24" {...base}><path d="M12 9v4M12 17h.01" /><path d="M10.3 3.9 2.4 18a2 2 0 0 0 1.7 3h15.8a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0Z" /></svg>);
export const IconBan = () => (<svg viewBox="0 0 24 24" {...base}><circle cx="12" cy="12" r="9" /><path d="m5.6 5.6 12.8 12.8" /></svg>);
export const IconClock = () => (<svg viewBox="0 0 24 24" {...base}><circle cx="12" cy="12" r="9" /><path d="M12 7v5l3 2" /></svg>);
export const IconPause = () => (<svg viewBox="0 0 24 24" {...base}><circle cx="12" cy="12" r="9" /><path d="M10 9v6M14 9v6" /></svg>);

export const BrandMark = () => <img src="/favicon.svg" width={34} height={34} alt="" />;
