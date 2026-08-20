"use client";

import React, { useState, useEffect, useRef } from "react";
import { useRouter } from "next/navigation";
import { appPath } from "@/lib/app-path";
import {
  useInitiateDeviceAuthMutation,
  usePollDeviceTokenMutation,
} from "@/services/auth";
import {
  Box,
  Card,
  CardContent,
  Button,
  Typography,
  Alert,
  Container,
  LinearProgress,
  Stack,
  Divider,
  Link,
  Paper,
  AppBar,
  Toolbar,
} from "@mui/material";
import { styled } from "@mui/material/styles";
import ContentCopyIcon from "@mui/icons-material/ContentCopy";
import CheckCircleIcon from "@mui/icons-material/CheckCircle";

const GradientBackground = styled(Box)(({ theme }) => ({
  minHeight: "100vh",
  backgroundColor: theme.palette.background.default,
  color: theme.palette.text.primary,
}));

const StyledCard = styled(Card)(({ theme }) => ({
  width: "100%",
  maxWidth: 560,
  boxShadow: "0 3px 12px rgba(23, 58, 92, 0.12)",
  borderRadius: theme.spacing(0.75),
  border: "1px solid",
  borderColor: theme.palette.divider,
}));

const GradientButton = styled(Button)(({ theme }) => ({
  backgroundColor: theme.palette.primary.main,
  color: theme.palette.primary.contrastText,
  padding: theme.spacing(1.25, 2),
  fontSize: "0.95rem",
  fontWeight: 600,
  textTransform: "none",
  transition: "transform 0.2s, box-shadow 0.2s",
  "&:hover": {
    backgroundColor: theme.palette.primary.dark,
    transform: "translateY(-1px)",
    boxShadow: "0 4px 12px rgba(0, 109, 207, 0.28)",
  },
  "&:disabled": {
    opacity: 0.6,
    transform: "none",
  },
}));

const CodeBox = styled(Paper)(({ theme }) => ({
  padding: theme.spacing(2.5),
  textAlign: "center",
  backgroundColor: "#f5f8fb",
  border: "1px solid #dbe5ee",
  borderRadius: theme.spacing(0.5),
}));

const LoginPage = () => {
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState("");
  const [deviceCode, setDeviceCode] = useState<string | null>(null);
  const [userCode, setUserCode] = useState<string | null>(null);
  const [verificationUri, setVerificationUri] = useState<string | null>(null);
  const [codeVerifier, setCodeVerifier] = useState<string | null>(null);
  const [pollInterval, setPollInterval] = useState<number>(5);
  const [copied, setCopied] = useState(false);
  const router = useRouter();
  const pollingRef = useRef<NodeJS.Timeout | null>(null);

  const [initiateDeviceAuth] = useInitiateDeviceAuthMutation();
  const [pollDeviceToken] = usePollDeviceTokenMutation();

  const startAuth = async () => {
    setIsLoading(true);
    setError("");

    try {
      const response = await initiateDeviceAuth().unwrap();

      setDeviceCode(response.device_code);
      setUserCode(response.user_code);
      setVerificationUri(response.verification_uri);
      setCodeVerifier(response.code_verifier);
      setPollInterval(response.interval || 5);
    } catch (err) {
      console.error("Device auth initiation failed:", err);
      setError("Failed to initiate authentication. Please try again.");
      setIsLoading(false);
    }
  };

  useEffect(() => {
    if (!deviceCode || !codeVerifier) return;

    const poll = async () => {
      try {
        const response = await pollDeviceToken({
          device_code: deviceCode,
          code_verifier: codeVerifier,
        }).unwrap();

        // Success! We got the tokens
        if (response.access_token) {
          if (pollingRef.current) {
            clearInterval(pollingRef.current);
          }
          router.push(appPath("/chat"));
        }
      } catch (err: unknown) {
        // Handle polling errors
        if (err && typeof err === "object" && "data" in err) {
          const errorData = err.data as { error?: string };
          if (errorData.error === "authorization_pending") {
            // Keep polling
            return;
          } else if (errorData.error === "slow_down") {
            // Increase poll interval
            setPollInterval((prev) => prev + 5);
            return;
          } else if (errorData.error === "access_denied") {
            setError("Authorization was denied.");
            if (pollingRef.current) {
              clearInterval(pollingRef.current);
            }
            setIsLoading(false);
          } else if (errorData.error === "expired_token") {
            setError("The authorization code has expired. Please try again.");
            if (pollingRef.current) {
              clearInterval(pollingRef.current);
            }
            setIsLoading(false);
          }
        } else {
          console.error("Token polling error:", err);
        }
      }
    };

    // Start polling
    pollingRef.current = setInterval(poll, pollInterval * 1000);

    return () => {
      if (pollingRef.current) {
        clearInterval(pollingRef.current);
      }
    };
  }, [deviceCode, codeVerifier, pollInterval, pollDeviceToken, router]);

  const copyToClipboard = () => {
    if (userCode) {
      navigator.clipboard.writeText(userCode);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }
  };

  const resetAuth = () => {
    if (pollingRef.current) {
      clearInterval(pollingRef.current);
    }
    setDeviceCode(null);
    setUserCode(null);
    setVerificationUri(null);
    setCodeVerifier(null);
    setIsLoading(false);
    setError("");
  };

  return (
    <GradientBackground>
      <AppBar position="static" elevation={0} color="primary">
        <Toolbar variant="dense" sx={{ minHeight: 48 }}>
          <Typography variant="subtitle1" sx={{ fontWeight: 600, fontSize: "0.9rem" }}>
            SAS Retrieval Agent Manager
          </Typography>
        </Toolbar>
      </AppBar>

      <Container maxWidth="sm" sx={{ py: { xs: 5, sm: 9 } }}>
        <StyledCard>
          <CardContent sx={{ p: { xs: 3, sm: 5 } }}>
            <Box mb={4}>
              <Typography
                variant="overline"
                color="primary"
                sx={{ fontWeight: 700, letterSpacing: "0.08em" }}
              >
                Secure access
              </Typography>
              <Typography
                variant="h5"
                component="h1"
                fontWeight={600}
                gutterBottom
                sx={{ mt: 0.5 }}
              >
                Sign in to Retrieval Agent Manager
              </Typography>
              <Typography variant="body2" color="text.secondary" sx={{ maxWidth: 440 }}>
                Access your collections and agents, and continue working with your chat sessions.
              </Typography>
            </Box>

            <Box sx={{ position: "relative" }}>
              {isLoading && (
                <LinearProgress
                  sx={{
                    position: "absolute",
                    top: -2,
                    left: 0,
                    right: 0,
                    borderRadius: 1,
                  }}
                />
              )}

              {!deviceCode ? (
                <Stack spacing={3}>
                  {error && (
                    <Alert severity="error" sx={{ borderRadius: 1 }}>
                      {error}
                    </Alert>
                  )}

                  <GradientButton
                    onClick={startAuth}
                    fullWidth
                    size="large"
                    disabled={isLoading}
                  >
                    {isLoading ? "Initializing..." : "Sign in with device code"}
                  </GradientButton>
                </Stack>
              ) : (
                <Stack spacing={3}>
                  <Typography
                    variant="body2"
                    color="text.secondary"
                    textAlign="center"
                  >
                    To complete authentication, copy the code below and visit
                    the verification URL:
                  </Typography>

                  <CodeBox elevation={0}>
                    <Typography
                      variant="caption"
                      color="text.secondary"
                      display="block"
                      mb={1}
                    >
                      User Code
                    </Typography>
                    <Box
                      sx={{
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        gap: 1,
                      }}
                    >
                      <Typography
                        variant="h4"
                        sx={{
                          fontFamily: "monospace",
                          fontWeight: 700,
                          letterSpacing: "0.1em",
                        }}
                      >
                        {userCode}
                      </Typography>
                      <Button
                        size="small"
                        onClick={copyToClipboard}
                        startIcon={
                          copied ? <CheckCircleIcon /> : <ContentCopyIcon />
                        }
                        sx={{ minWidth: "auto" }}
                      >
                        {copied ? "Copied!" : "Copy"}
                      </Button>
                    </Box>
                  </CodeBox>

                  <Divider />

                  <CodeBox elevation={0}>
                    <Typography
                      variant="caption"
                      color="text.secondary"
                      display="block"
                      mb={1}
                    >
                      Verification URL
                    </Typography>
                    <Link
                      href={verificationUri || "#"}
                      target="_blank"
                      rel="noopener noreferrer"
                      sx={{
                        fontSize: "1rem",
                        fontWeight: 500,
                        textDecoration: "none",
                        wordBreak: "break-word",
                        overflowWrap: "break-word",
                        display: "inline-block",
                        maxWidth: "100%",
                        "&:hover": { textDecoration: "underline" },
                      }}
                    >
                      {verificationUri}
                    </Link>
                  </CodeBox>

                  {error && (
                    <Alert severity="error" sx={{ borderRadius: 1 }}>
                      {error}
                    </Alert>
                  )}

                  <Alert severity="info" sx={{ borderRadius: 1 }}>
                    Waiting for authorization... This page will automatically
                    redirect once you complete the authentication.
                  </Alert>

                  <Button
                    onClick={resetAuth}
                    variant="outlined"
                    fullWidth
                    disabled={!error}
                  >
                    Cancel
                  </Button>
                </Stack>
              )}
            </Box>
          </CardContent>
        </StyledCard>
        <Typography
          variant="caption"
          color="text.secondary"
          display="block"
          textAlign="center"
          sx={{ mt: 2.5 }}
        >
          Authentication is managed by your organization.
        </Typography>
      </Container>
    </GradientBackground>
  );
};

export default LoginPage;
