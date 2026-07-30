'use client';

import React from 'react';
import { CacheProvider } from '@emotion/react';
import createCache from '@emotion/cache';
import { prefixer } from 'stylis';
import rtlPlugin from 'stylis-plugin-rtl';

const cacheRtl = createCache({
  key: 'muirtl',
  stylisPlugins: [prefixer, rtlPlugin],
});

const cacheLtr = createCache({
  key: 'muiltr',
});

interface RTLProps {
  children: React.ReactNode;
  direction: 'ltr' | 'rtl';
}

export function RTLProvider({ children, direction }: RTLProps) {
  const cache = direction === 'rtl' ? cacheRtl : cacheLtr;

  return <CacheProvider value={cache}>{children}</CacheProvider>;
}
