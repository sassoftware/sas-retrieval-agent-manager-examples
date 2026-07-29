import { Geist, Geist_Mono } from 'next/font/google';
import './globals.css';
import App from './App';
import AuthWrapper from './AuthWrapper';
import StoreWrapper from './StoreWrapper';
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

export default async function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  // Read request headers to detect Preferred language dynamically
  const headersList = await headers();
  const acceptLanguage = headersList.get('accept-language') || 'en';

  // Determine if the user's preferred language is Hebrew ('he')
  const isHebrew = acceptLanguage.startsWith('he') || acceptLanguage.includes('he-IL');

  const locale = isHebrew ? 'he' : 'en';
  const direction = isHebrew ? 'rtl' : 'ltr';

  return (
    <html lang={locale} dir={direction}>
      <body className={`${geistSans.variable} ${geistMono.variable}`}>
        <StoreWrapper>
          <AuthWrapper>
            <RTLProvider direction={direction}>
              <App>{children}</App>
            </RTLProvider>
          </AuthWrapper>
        </StoreWrapper>
      </body>
    </html>
  );
}
