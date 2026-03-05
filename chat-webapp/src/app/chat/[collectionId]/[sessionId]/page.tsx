'use client';
import { Box, Typography, Paper, TextField, IconButton, Stack } from "@mui/material";
import { Send as SendIcon, Error as ErrorIcon } from "@mui/icons-material";
import { use, useEffect, useMemo, useState } from "react";
import { useAppSelector } from "@/store";
import { useSendQueryMutation, useGetQuerySessionQuery } from "@/services/chat";
import { useRouter } from "next/navigation";

interface Message {
    id: string;
    content: string;
    isUser: boolean;
    isError?: boolean;
    isLoading?: boolean;
    timestamp: Date;
}

export default function Page({ params }: { params: Promise<{ collectionId: string, sessionId: string }> }) {
    const { collectionId, sessionId } = use(params);
    const [sendQuery] = useSendQueryMutation();
    const { data: querySessionData, refetch } = useGetQuerySessionQuery(sessionId, {
        skip: sessionId === 'new'
    });
    const allSessions = useAppSelector(state => state.chat.sessions);
    const router = useRouter();

    const thisSession = useMemo(() => {
        return allSessions.find(session => session.id === sessionId);
    }, [sessionId, allSessions]);

    const queries = useMemo(() => {
        return querySessionData?.items || [];
    }, [querySessionData]);

    const messages: Message[] = useMemo(() => {
        return queries.flatMap(q => {
            const m: Message[] = [{
                id: q.id + '-user',
                content: q.content,
                isUser: true,
                timestamp: new Date(q.update_timestamp),
            }];
            if (q.response?.answer) {
                m.push({
                    id: q.id + '-ai',
                    content: q.response.answer,
                    isUser: false,
                    timestamp: new Date(q.update_timestamp),
                });
            } else if (q.errors_text) {
                m.push({
                    id: q.id + '-error',
                    content: q.errors_text,
                    isUser: false,
                    isError: true,
                    timestamp: new Date(q.update_timestamp),
                });
            }
            return m;
        })
    }, [queries]);

    const [inputValue, setInputValue] = useState("");
    const [pendingMessages, setPendingMessages] = useState<Message[]>([]);

    useEffect(() => console.log(messages), [messages]);

    // Combine actual messages with pending messages
    const allMessages = useMemo(() => {
        return [...messages, ...pendingMessages];
    }, [messages, pendingMessages]);

    const handleSendMessage = async () => {
        if (!inputValue.trim()) return;

        const messageContent = inputValue.trim();
        const tempId = `temp-${Date.now()}`;

        // Clear input and add pending message
        setInputValue("");

        // Add user message immediately
        const userMessage: Message = {
            id: tempId + '-user',
            content: messageContent,
            isUser: true,
            timestamp: new Date(),
        };

        // Add loading AI response
        const loadingMessage: Message = {
            id: tempId + '-loading',
            content: 'Thinking...',
            isUser: false,
            isLoading: true,
            timestamp: new Date(),
        };

        setPendingMessages([userMessage, loadingMessage]);

        try {
            const query = await sendQuery({
                content: messageContent,
                collectionIds: [collectionId],
                querySessionId: thisSession?.id,
            }).unwrap();

            // Clear pending messages since real messages will be updated via Redux
            setPendingMessages([]);

            if (query?.querySessionId) {
                // If same session, refetch to get new data; if different session, navigate
                if (query.querySessionId === sessionId) {
                    refetch();
                } else {
                    router.replace(`/chat/${collectionId}/${query.querySessionId}`);
                }
            }
        } catch {
            // On error, replace loading message with error message
            setPendingMessages([
                userMessage,
                {
                    id: tempId + '-error',
                    content: 'Failed to send message. Please try again.',
                    isUser: false,
                    isError: true,
                    timestamp: new Date(),
                }
            ]);
        }
    };

    const handleKeyPress = (e: React.KeyboardEvent) => {
        if (e.key === "Enter" && !e.shiftKey) {
            e.preventDefault();
            handleSendMessage();
        }
    };

    const sessionTitle = useMemo(() => thisSession?.title ?? 'New Session', [thisSession]);

    return (
        <Box
            sx={{
                height: "100vh",
                display: "flex",
                flexDirection: "column",
                pt: 8, // Account for AppBar height (64px = 8 * 8px)
            }}
        >
            {/* Session Header */}
            <Box sx={{ p: 2, borderBottom: 1, borderColor: "divider", backgroundColor: "background.paper" }}>
                <Typography variant="h6">
                    {sessionTitle}
                </Typography>
            </Box>

            {/* Messages Area */}
            <Box
                sx={{
                    flex: 1,
                    overflow: "auto",
                    p: 2,
                    display: "flex",
                    flexDirection: "column",
                    gap: 1,
                }}
            >
                {allMessages.map((message) => (
                    <Box
                        key={message.id}
                        sx={{
                            display: "flex",
                            justifyContent: message.isUser ? "flex-end" : "flex-start",
                            mb: 1,
                        }}
                    >
                        <Paper
                            elevation={1}
                            sx={{
                                p: 2,
                                maxWidth: "70%",
                                backgroundColor: message.isUser
                                    ? "primary.main"
                                    : message.isError
                                        ? "error.light"
                                        : "background.paper",
                                color: message.isUser
                                    ? "primary.contrastText"
                                    : message.isError
                                        ? "error.contrastText"
                                        : "text.primary",
                                border: message.isError ? 1 : 0,
                                borderColor: message.isError ? "error.main" : "transparent",
                            }}
                        >
                            <Box sx={{ display: "flex", alignItems: "flex-start", gap: 1 }}>
                                {message.isError && (
                                    <ErrorIcon sx={{ color: "error.main", fontSize: 20, mt: 0.2 }} />
                                )}
                                <Typography
                                    variant="body1"
                                    sx={{
                                        flex: 1,
                                        opacity: message.isLoading ? 0.7 : 1,
                                        fontStyle: message.isLoading ? 'italic' : 'normal',
                                        whiteSpace: 'pre-wrap',
                                    }}
                                >
                                    {message.isError ? `Error: ${message.content}` : message.content}
                                    {message.isLoading && (
                                        <Box component="span" sx={{ ml: 1 }}>
                                            <Box
                                                component="span"
                                                sx={{
                                                    display: 'inline-block',
                                                    width: 4,
                                                    height: 4,
                                                    bgcolor: 'text.secondary',
                                                    borderRadius: '50%',
                                                    animation: 'pulse 1.5s ease-in-out infinite',
                                                    '@keyframes pulse': {
                                                        '0%': { opacity: 0.3 },
                                                        '50%': { opacity: 1 },
                                                        '100%': { opacity: 0.3 }
                                                    }
                                                }}
                                            />
                                        </Box>
                                    )}
                                </Typography>
                            </Box>
                            <Typography
                                variant="caption"
                                sx={{
                                    opacity: 0.7,
                                    display: "block",
                                    mt: 0.5,
                                }}
                            >
                                {message.timestamp.toLocaleTimeString()}
                            </Typography>
                        </Paper>
                    </Box>
                ))}
            </Box>

            {/* Input Area */}
            <Box
                sx={{
                    p: 2,
                    borderTop: 1,
                    borderColor: "divider",
                    backgroundColor: "background.paper",
                }}
            >
                <Stack direction="row" spacing={1} alignItems="flex-end">
                    <TextField
                        fullWidth
                        multiline
                        maxRows={4}
                        placeholder="Type your message..."
                        value={inputValue}
                        onChange={(e) => setInputValue(e.target.value)}
                        onKeyPress={handleKeyPress}
                        variant="outlined"
                        size="small"
                    />
                    <IconButton
                        color="primary"
                        onClick={handleSendMessage}
                        disabled={!inputValue.trim()}
                        sx={{ mb: 0.5 }}
                    >
                        <SendIcon />
                    </IconButton>
                </Stack>
            </Box>
        </Box>
    );
}