import { createTheme } from '@mui/material/styles';

export const sasTheme = createTheme({
  palette: {
    primary: {
      main: '#006DCF',       // SAS blue
      contrastText: '#ffffff',
    },
    secondary: {
      main: '#006DCF',       // SAS blue
      contrastText: '#ffffff',
    },
    background: {
      default: '#f5f5f5',
      paper: '#ffffff',
    },
  },
  typography: {
    fontFamily: '"SAS Sans", "Helvetica Neue", Arial, sans-serif',
  },
});
