'use client';

import { ThemeProvider } from '@mui/material/styles';
import CssBaseline from '@mui/material/CssBaseline';
import { sasTheme } from './theme';

export default function ThemeRegistry({ children }: { children: React.ReactNode }) {
  return (
    <ThemeProvider theme={sasTheme}>
      <CssBaseline />
      {children}
    </ThemeProvider>
  );
}
