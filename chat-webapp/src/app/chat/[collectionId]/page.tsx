'use client';
import { Box, Button, Typography } from "@mui/material";
import { useRouter } from "next/navigation";
import { use } from "react";
import { appPath } from "@/lib/app-path";


export default function Page({ params }: { params: Promise<{ collectionId: string }> }) {
    const router = useRouter();
    const { collectionId } = use(params);
    return (
        <Box sx={{
            border: 'solid red 1px',
            // pt: 8, // Account for AppBar height (64px = 8 * 8px)
            // p: 2,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            flexDirection: 'column',
            height: '100vh',
        }}>
            <Typography variant="h6" gutterBottom>Select a session from the sidebar or start a new one</Typography>
            <Button variant="contained" onClick={() => router.replace(appPath(`/chat/${collectionId}/new`))}>
                Start New Chat
            </Button>
        </Box>
    );
}