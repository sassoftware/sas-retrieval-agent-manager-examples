import { Geist, Geist_Mono } from 'next/font/google';
import './globals.css';
import App from './App';
import AuthWrapper from './AuthWrapper';
import StoreWrapper from './StoreWrapper';
import ThemeRegistry from './ThemeRegistry';
import { RTLProvider } from '../providers/RTLProvider';
import { headers } from 'next/headers';

const geistSans = Geist({
  variable: '--font-geist-sans',
  subsets: ['latin'],
});

const geistMono = Geist_Mono({
  variable: '--font-geist-mono',
  subsets: ['latin'],
});

// List of standard RTL language codes
const RTL_LANGUAGES = new Set(['ar', 'he', 'fa', 'ur', 'yi', 'ps', 'dv', 'ug', 'iw']);

export default async function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  // Read request headers to detect Preferred language dynamically
  const headersList = await headers();
  const acceptLanguage = headersList.get('accept-language') || 'en';

  // Get the primary language tag (e.g., "he-IL" -> "he", "ar-EG" -> "ar")
  const primaryLocale = acceptLanguage.split(',')[0].split('-')[0].toLowerCase().trim();

  const isRtl = RTL_LANGUAGES.has(primaryLocale);
  const locale = primaryLocale;
  const direction = isRtl ? 'rtl' : 'ltr';

  return (
    <html lang={locale} dir={direction}>
      <body className={`${geistSans.variable} ${geistMono.variable}`}>
        <ThemeRegistry>
          <StoreWrapper>
            <AuthWrapper>
              <RTLProvider direction={direction}>
                <App>{children}</App>
              </RTLProvider>
            </AuthWrapper>
          </StoreWrapper>
        </ThemeRegistry>
      </body>
    </html>
  );
}
