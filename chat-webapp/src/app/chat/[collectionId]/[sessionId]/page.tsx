'use client';
import { Box, Typography, Paper, TextField, IconButton, Stack, Chip } from "@mui/material";
import { Send as SendIcon, Error as ErrorIcon, AttachFile as AttachFileIcon, Close as CloseIcon, Image as ImageIcon, InsertDriveFile as FileIcon } from "@mui/icons-material";
import { use, useEffect, useMemo, useRef, useState } from "react";
import { useAppSelector } from "@/store";
import { useSendQueryMutation, useGetAgentsQuery, useGetQuerySessionQuery } from "@/services/chat";
import { useRouter } from "next/navigation";
import { Query, QueryFileContent, QueryImageContent } from "@/types/query";
import { appPath } from "@/lib/app-path";

interface Message {
    id: string;
    content: string;
    isUser: boolean;
    isError?: boolean;
    isLoading?: boolean;
    timestamp: Date;
    imageUrls?: string[];
    attachments?: Array<{ name: string; mimeType: string; kind: "image" | "file" }>;
}

type MessageMetadata = Pick<Message, "timestamp" | "imageUrls" | "attachments">;
type StoredMessageMetadata = Omit<MessageMetadata, "timestamp"> & { timestamp: string };

interface SelectedImage extends QueryImageContent {
    id: string;
    name: string;
}

interface SelectedFile extends QueryFileContent {
    id: string;
    name: string;
}

type ImageMimeType = "image/png" | "image/jpeg" | "image/webp" | "image/gif";
type FileMimeType = "application/pdf" | "text/plain" | "text/markdown" | "text/csv" | "application/json";
const ACCEPTED_FILE_TYPES = "image/png,image/jpeg,image/webp,image/gif,application/pdf,text/plain,text/markdown,text/csv,application/json";
const FILE_MIME_TYPES = new Set<FileMimeType>([
    "application/pdf",
    "text/plain",
    "text/markdown",
    "text/csv",
    "application/json",
]);
const IMAGE_MIME_TYPES = new Set<ImageMimeType>(["image/png", "image/jpeg", "image/webp", "image/gif"]);
const encodeImage = (file: File): Promise<string> => new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
        if (typeof reader.result !== "string") {
            reject(new Error("Unable to read image"));
            return;
        }
        resolve(reader.result.split(",", 2)[1] || "");
    };
    reader.onerror = () => reject(reader.error ?? new Error("Unable to read image"));
    reader.readAsDataURL(file);
});

const getQueryDisplayContent = (content: string | Array<{ role: "user"; content: Array<{ type: "text"; text: string } | QueryImageContent | QueryFileContent> }>): string => {
    if (typeof content === "string") return content;

    const blocks = content.flatMap((message) => message.content);
    const text = blocks
        .filter((block): block is { type: "text"; text: string } => block.type === "text")
        .map((block) => block.text)
        .join("\n");
    const attachmentCount = blocks.filter((block) => block.type === "image" || block.type === "file").length;
    const attachment = attachmentCount > 0
        ? `Attached ${attachmentCount} file${attachmentCount === 1 ? "" : "s"}`
        : "";

    return [text, attachment].filter(Boolean).join("\n");
};

const getQueryImageUrls = (content: string | Array<{ role: "user"; content: Array<{ type: "text"; text: string } | QueryImageContent | QueryFileContent> }>): string[] => {
    if (typeof content === "string") return [];

    return content.flatMap((message) => message.content)
        .filter((block): block is QueryImageContent => block.type === "image")
        .map((block) => `data:${block.mime_type};base64,${block.base64}`);
};

const getQueryAttachments = (content: string | Array<{ role: "user"; content: Array<{ type: "text"; text: string } | QueryImageContent | QueryFileContent> }>) => {
    if (typeof content === "string") return [];

    return content.flatMap((message) => message.content)
        .filter((block): block is QueryImageContent | QueryFileContent => block.type === "image" || block.type === "file")
        .map((block) => ({ name: block.extras.name, mimeType: block.mime_type, kind: block.type }));
};

const renderMarkdown = (text: string) => text.split(/(\*\*[^*\n]+\*\*)/g).map((part, index) =>
    part.startsWith("**") && part.endsWith("**")
        ? <strong key={`${part}-${index}`}>{part.slice(2, -2)}</strong>
        : part
);

const formatTimestamp = (date: Date): string => {
    return Number.isNaN(date.getTime()) ? "" : date.toLocaleTimeString();
};

const getQueryTimestamp = (query: Query, fallback?: Date): Date => {
    const queryWithAlternateTimestamp = query as Query & {
        insert_timestamp?: string;
        insertTimestamp?: string;
        timestamp?: string;
    };
    const value = query.update_timestamp || queryWithAlternateTimestamp.insert_timestamp
        || queryWithAlternateTimestamp.insertTimestamp || queryWithAlternateTimestamp.timestamp;
    const timestamp = value ? new Date(value) : new Date(NaN);
    return Number.isNaN(timestamp.getTime()) ? (fallback ?? new Date()) : timestamp;
};

const metadataStorageKey = (collectionId: string) => `chat-message-metadata:${collectionId}`;

export default function Page({ params }: { params: Promise<{ collectionId: string, sessionId: string }> }) {
    const { collectionId, sessionId } = use(params);
    const [sendQuery] = useSendQueryMutation();
    const { data: agentsResponse } = useGetAgentsQuery();
    const [activeQuerySessionId, setActiveQuerySessionId] = useState<string | null>(
        sessionId === 'new' ? null : sessionId
    );
    const { data: querySessionData, refetch } = useGetQuerySessionQuery(activeQuerySessionId ?? '', {
        skip: !activeQuerySessionId
    });
    const allSessions = useAppSelector(state => state.chat.sessions);
    const router = useRouter();
    const isAgentChat = agentsResponse?.items.some(agent => agent.id === collectionId) ?? false;
    const [messageMetadata, setMessageMetadata] = useState<Record<string, StoredMessageMetadata>>({});

    useEffect(() => {
        setActiveQuerySessionId(sessionId === 'new' ? null : sessionId);
    }, [sessionId]);

    const thisSession = useMemo(() => {
        return allSessions.find(session => session.id === activeQuerySessionId);
    }, [activeQuerySessionId, allSessions]);

    const queries = useMemo(() => {
        return querySessionData?.items || [];
    }, [querySessionData]);

    const messages: Message[] = useMemo(() => {
        return queries
        // Agent orchestration calls are implementation details, not user turns.
        .filter(q => !isAgentChat || !q.parentQueryId)
        // RAM returns session queries newest-first.
        .slice()
        .reverse()
        .flatMap(q => {
            const stored = messageMetadata[q.id];
            const storedMetadata = stored ? {
                ...stored,
                timestamp: new Date(stored.timestamp),
            } : undefined;
            const queryAttachments = getQueryAttachments(q.content);
            const queryImageUrls = getQueryImageUrls(q.content);
            const timestamp = storedMetadata?.timestamp ?? getQueryTimestamp(q);
            const m: Message[] = [{
                id: q.id + '-user',
                content: getQueryDisplayContent(q.content),
                isUser: true,
                timestamp,
                imageUrls: queryImageUrls.length > 0 ? queryImageUrls : storedMetadata?.imageUrls,
                attachments: queryAttachments.length > 0 ? queryAttachments : storedMetadata?.attachments,
            }];
            if (q.response?.answer) {
                m.push({
                    id: q.id + '-ai',
                    content: q.response.answer,
                    isUser: false,
                    timestamp,
                });
            } else if (q.errors_text) {
                m.push({
                    id: q.id + '-error',
                    content: q.errors_text,
                    isUser: false,
                    isError: true,
                    timestamp,
                });
            }
            return m;
        })
    }, [queries, isAgentChat, messageMetadata]);

    const [inputValue, setInputValue] = useState("");
    const [selectedImages, setSelectedImages] = useState<SelectedImage[]>([]);
    const [selectedFiles, setSelectedFiles] = useState<SelectedFile[]>([]);
    const [isReadingImages, setIsReadingImages] = useState(false);
    const fileInputRef = useRef<HTMLInputElement>(null);
    const [pendingMessages, setPendingMessages] = useState<Message[]>([]);

    useEffect(() => {
        try {
            const stored = localStorage.getItem(metadataStorageKey(collectionId));
            if (stored) setMessageMetadata(JSON.parse(stored));
        } catch {
            // Ignore malformed or unavailable browser storage.
        }
    }, [collectionId]);

    const rememberMessageMetadata = (queryId: string, metadata: MessageMetadata) => {
        const storedMetadata: StoredMessageMetadata = {
            ...metadata,
            timestamp: metadata.timestamp.toISOString(),
        };
        setMessageMetadata((previous) => {
            const next = { ...previous, [queryId]: storedMetadata };
            try {
                localStorage.setItem(metadataStorageKey(collectionId), JSON.stringify(next));
            } catch {
                // Metadata is still available for the current view if storage is unavailable.
            }
            return next;
        });
    };

    // Combine actual messages with pending messages
    const allMessages = useMemo(() => {
        return [...messages, ...pendingMessages];
    }, [messages, pendingMessages]);

    const handleSendMessage = async () => {
        if (!inputValue.trim() && selectedImages.length === 0 && selectedFiles.length === 0) return;
        if ((selectedImages.length > 0 || selectedFiles.length > 0) && !isAgentChat) return;

        const messageContent = inputValue.trim();
        const imagesToSend = selectedImages;
        const filesToSend = selectedFiles;
        const tempId = `temp-${Date.now()}`;

        // Clear input and add pending message
        setInputValue("");
        setSelectedImages([]);
        setSelectedFiles([]);

        // Add user message immediately
        const userMessage: Message = {
            id: tempId + '-user',
            content: messageContent || `Attached ${imagesToSend.length + filesToSend.length} file${imagesToSend.length + filesToSend.length === 1 ? "" : "s"}`,
            isUser: true,
            timestamp: new Date(),
            imageUrls: imagesToSend.map((image) => `data:${image.mime_type};base64,${image.base64}`),
            attachments: [
                ...imagesToSend.map((image) => ({ name: image.extras.name, mimeType: image.mime_type, kind: "image" as const })),
                ...filesToSend.map((file) => ({ name: file.extras.name, mimeType: file.mime_type, kind: "file" as const })),
            ],
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
            const content = imagesToSend.length > 0 || filesToSend.length > 0
                ? [{
                    role: "user" as const,
                    content: [
                        ...(messageContent ? [{ type: "text" as const, text: messageContent }] : []),
                        ...imagesToSend.map((image) => ({
                            type: image.type,
                            mime_type: image.mime_type,
                            base64: image.base64,
                            extras: image.extras,
                        })),
                        ...filesToSend.map((file) => ({
                            type: file.type,
                            mime_type: file.mime_type,
                            base64: file.base64,
                            extras: file.extras,
                        })),
                    ],
                }]
                : messageContent;

            const query = await sendQuery({
                content,
                ...(isAgentChat ? { agentId: collectionId } : { collectionIds: [collectionId] }),
                querySessionId: activeQuerySessionId ?? undefined,
            }).unwrap();

            if (query?.id) {
                rememberMessageMetadata(query.id, {
                    timestamp: userMessage.timestamp,
                    imageUrls: userMessage.imageUrls,
                    attachments: userMessage.attachments,
                });
            }

            // Clear pending messages since real messages will be updated via Redux
            setPendingMessages([]);

            if (query?.querySessionId) {
                // If same session, refetch to get new data; if different session, navigate
                if (query.querySessionId === activeQuerySessionId) {
                    refetch();
                } else {
                    setActiveQuerySessionId(query.querySessionId);
                    router.replace(appPath(`/chat/${collectionId}/${query.querySessionId}`));
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

    const handleImageChange = async (event: React.ChangeEvent<HTMLInputElement>) => {
        const files = Array.from(event.target.files ?? []);
        event.target.value = "";
        if (files.length === 0) return;

        setIsReadingImages(true);
        try {
            const attachments = await Promise.all(files.map(async (file) => {
                if (IMAGE_MIME_TYPES.has(file.type as ImageMimeType)) {
                    return {
                        kind: "image" as const,
                        attachment: {
                            id: `${file.name}-${file.lastModified}-${crypto.randomUUID()}`,
                            name: file.name,
                            base64: await encodeImage(file),
                            extras: { name: file.name, size_bytes: file.size },
                            mime_type: file.type as SelectedImage["mime_type"],
                            type: "image" as const,
                        },
                    };
                }
                if (FILE_MIME_TYPES.has(file.type as FileMimeType)) {
                    return {
                        kind: "file" as const,
                        attachment: {
                            id: `${file.name}-${file.lastModified}-${crypto.randomUUID()}`,
                            name: file.name,
                            base64: await encodeImage(file),
                            extras: { name: file.name, size_bytes: file.size },
                            mime_type: file.type as SelectedFile["mime_type"],
                            type: "file" as const,
                        },
                    };
                }
                return null;
            }));
            const images = attachments.filter((item): item is { kind: "image"; attachment: SelectedImage } => item?.kind === "image").map((item) => item.attachment);
            const documents = attachments.filter((item): item is { kind: "file"; attachment: SelectedFile } => item?.kind === "file").map((item) => item.attachment);
            setSelectedImages((previous) => [...previous, ...images]);
            setSelectedFiles((previous) => [...previous, ...documents]);
        } catch {
            setPendingMessages([{
                id: `image-error-${Date.now()}`,
                content: "Unable to read the selected image. Please try again.",
                isUser: false,
                isError: true,
                timestamp: new Date(),
            }]);
        } finally {
            setIsReadingImages(false);
        }
    };

    const handleKeyPress = (e: React.KeyboardEvent) => {
        if (e.key === "Enter" && !e.shiftKey) {
            e.preventDefault();
            handleSendMessage();
        }
    };

    const sessionTitle = useMemo(() => thisSession?.title ?? (isAgentChat ? 'New Agent Chat' : 'New Session'), [thisSession, isAgentChat]);

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
                                    {message.isError ? message.content : renderMarkdown(message.content)}
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
                                {formatTimestamp(message.timestamp)}
                            </Typography>
                            {message.imageUrls?.map((imageUrl, index) => (
                                <Box
                                    component="img"
                                    key={`${message.id}-image-${index}`}
                                    src={imageUrl}
                                    alt={`Attached image ${index + 1}`}
                                    sx={{
                                        display: "block",
                                        maxWidth: 240,
                                        maxHeight: 180,
                                        objectFit: "contain",
                                        borderRadius: 1,
                                        mt: 1,
                                    }}
                                />
                            ))}
                            {message.attachments?.map((attachment, index) => (
                            <Box
                                    key={`${message.id}-attachment-${index}`}
                                    sx={{
                                        display: "flex",
                                        alignItems: "center",
                                        gap: 1,
                                        mt: 1,
                                        px: 1.25,
                                        py: 0.75,
                                        borderRadius: 1,
                                        backgroundColor: message.isUser ? "rgba(255,255,255,0.16)" : "action.hover",
                                    }}
                                >
                                    {attachment.kind === "image" ? <ImageIcon fontSize="small" /> : <FileIcon fontSize="small" />}
                                    <Typography variant="caption" sx={{ wordBreak: "break-word" }}>
                                        {attachment.name}
                                    </Typography>
                                </Box>
                            ))}
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
                    <input
                        ref={fileInputRef}
                        type="file"
                        accept={ACCEPTED_FILE_TYPES}
                        multiple
                        hidden
                        onChange={handleImageChange}
                    />
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
                        disabled={(!inputValue.trim() && selectedImages.length === 0 && selectedFiles.length === 0) || isReadingImages || ((selectedImages.length > 0 || selectedFiles.length > 0) && !isAgentChat)}
                        sx={{ mb: 0.5 }}
                    >
                        <SendIcon />
                    </IconButton>
                    <IconButton
                        color="primary"
                        aria-label="Attach images"
                        onClick={() => fileInputRef.current?.click()}
                        disabled={!isAgentChat || isReadingImages}
                        sx={{ mb: 0.5 }}
                    >
                        <AttachFileIcon />
                    </IconButton>
                </Stack>
                {selectedImages.length > 0 && (
                    <Stack direction="row" spacing={1} flexWrap="wrap" useFlexGap sx={{ mt: 1 }}>
                        {selectedImages.map((image) => (
                            <Chip
                                key={image.id}
                                label={image.name}
                                icon={<ImageIcon />}
                                onDelete={() => setSelectedImages((previous) => previous.filter((item) => item.id !== image.id))}
                                deleteIcon={<CloseIcon />}
                            />
                        ))}
                    </Stack>
                )}
                {selectedFiles.length > 0 && (
                    <Stack direction="row" spacing={1} flexWrap="wrap" useFlexGap sx={{ mt: 1 }}>
                        {selectedFiles.map((file) => (
                            <Chip
                                key={file.id}
                                label={file.name}
                                icon={<FileIcon />}
                                onDelete={() => setSelectedFiles((previous) => previous.filter((item) => item.id !== file.id))}
                                deleteIcon={<CloseIcon />}
                            />
                        ))}
                    </Stack>
                )}
            </Box>
        </Box>
    );
}
