"use client";

import { useAppSelector } from "@/store";
import { useEffect, useState } from "react";
import {
  Box,
  Card,
  CardContent,
  Typography,
  Container,
  Alert,
  CircularProgress,
} from "@mui/material";

interface TokenInfo {
  header: Record<string, unknown>;
  payload: Record<string, unknown>;
}

export default function DebugTokenPage() {
  const access_token = useAppSelector((state) => state.auth.access_token);
  const [tokenInfo, setTokenInfo] = useState<TokenInfo | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!access_token) return;

    const decodeToken = () => {
      setLoading(true);
      setError(null);
      try {
        const parts = access_token.split(".");
        if (parts.length !== 3) {
          throw new Error("Invalid JWT format");
        }

        const header = JSON.parse(atob(parts[0]));
        const payload = JSON.parse(atob(parts[1]));

        setTokenInfo({ header, payload });
      } catch (err) {
        setError(String(err));
      } finally {
        setLoading(false);
      }
    };

    decodeToken();
  }, [access_token]);

  if (!access_token) {
    return (
      <Container maxWidth="lg" sx={{ py: 4 }}>
        <Alert severity="warning">
          No access token found. Please log in first.
        </Alert>
      </Container>
    );
  }

  return (
    <Container maxWidth="lg" sx={{ py: 4 }}>
      <Typography variant="h4" gutterBottom>
        Access Token Debug
      </Typography>

      {loading && <CircularProgress />}

      {error && (
        <Alert severity="error" sx={{ mb: 2 }}>
          Error decoding token: {error}
        </Alert>
      )}

      {tokenInfo && (
        <>
          <Card sx={{ mb: 3 }}>
            <CardContent>
              <Typography variant="h6" gutterBottom>
                Token Header
              </Typography>
              <Box
                component="pre"
                sx={{
                  bgcolor: "grey.100",
                  p: 2,
                  borderRadius: 1,
                  overflow: "auto",
                  fontSize: "0.875rem",
                }}
              >
                {JSON.stringify(tokenInfo.header, null, 2)}
              </Box>
            </CardContent>
          </Card>

          <Card sx={{ mb: 3 }}>
            <CardContent>
              <Typography variant="h6" gutterBottom>
                Token Payload (Claims)
              </Typography>
              <Box
                component="pre"
                sx={{
                  bgcolor: "grey.100",
                  p: 2,
                  borderRadius: 1,
                  overflow: "auto",
                  fontSize: "0.875rem",
                }}
              >
                {JSON.stringify(tokenInfo.payload, null, 2)}
              </Box>
            </CardContent>
          </Card>

          <Alert severity="info">
            <Typography variant="body2" fontWeight="bold" gutterBottom>
              Check for group membership in:
            </Typography>
            <ul style={{ marginTop: 8, marginBottom: 0 }}>
              <li>
                <code>groups</code> - direct groups array
              </li>
              <li>
                <code>realm_access.roles</code> - realm-level roles
              </li>
              <li>
                <code>resource_access[clientId].roles</code> - client-specific
                roles
              </li>
            </ul>
          </Alert>
        </>
      )}
    </Container>
  );
}
