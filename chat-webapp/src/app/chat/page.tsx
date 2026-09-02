'use client'
import { useGetCollectionsQuery, useGetSessionsQuery } from "@/services/chat";
import { useAppSelector } from "@/store";
import {
    Box,
    Typography,
    Card,
    CardContent,
    Container,
    CardActionArea,
    Chip,
    Stack,
    ToggleButton,
    ToggleButtonGroup,
} from "@mui/material";
import { useRouter } from "next/navigation";
import { styled } from "@mui/material/styles";
import ChatIcon from '@mui/icons-material/Chat';
import SmartToyIcon from '@mui/icons-material/SmartToy';
import Link from "next/link";
import { appPath } from "@/lib/app-path";
import TopBar from "@/app/TopBar";

const StyledCard = styled(Card)(({ theme }) => ({
    height: '100%',
    display: 'flex',
    flexDirection: 'column',
    border: `1px solid ${theme.palette.divider}`,
    borderRadius: 2,
    transition: 'transform 0.2s ease, box-shadow 0.2s ease',
    cursor: 'pointer',
    '&:hover': {
        transform: 'translateY(-2px)',
        boxShadow: theme.shadows[3],
    },
    '&:active': {
        transform: 'translateY(-2px)',
    },
}));

const StyledCardActionArea = styled(CardActionArea)(({ theme }) => ({
    height: '100%',
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'stretch',
    '&:hover .card-content': {
        backgroundColor: theme.palette.action.hover,
    },
}));

const IconContainer = styled(Box)(({ theme }) => ({
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    width: 40,
    height: 40,
    borderRadius: 1.5,
    backgroundColor: theme.palette.primary.main,
    color: theme.palette.primary.contrastText,
    marginBottom: theme.spacing(1.5),
}));

export default function Page() {

    const { isLoading } = useGetCollectionsQuery();
    useGetSessionsQuery();

    const collections = useAppSelector(state => state.chat.collections ?? []);

    const router = useRouter();

    const handleCardClick = (collectionId: string) => {
        router.push(appPath(`/chat/${collectionId}`));
    };

    return (
        <>
            <TopBar title="SAS Retrieval Agent Manager" />
            <Container maxWidth="lg" sx={{ py: { xs: 3, md: 5 }, pt: { xs: 11, md: 13 } }}>
            <Box sx={{ mb: 4, display: 'flex', alignItems: { xs: 'flex-start', md: 'center' }, justifyContent: 'space-between', flexWrap: 'wrap', gap: 3 }}>
                <Box>
                    <Typography variant="h4" component="h1" sx={{ fontWeight: 700, letterSpacing: '-0.02em', mb: 0.5 }}>
                        Collections
                    </Typography>
                    <Typography variant="body1" color="text.secondary">
                        Select a collection to start chatting
                    </Typography>
                </Box>
                <ToggleButtonGroup exclusive value="collections" size="small" aria-label="Browse agents or collections">
                    <ToggleButton value="agents" component={Link} href={appPath("/agents")} sx={{ px: 2, minWidth: 108, textTransform: 'none' }}>
                        <SmartToyIcon sx={{ mr: 0.75, fontSize: 18 }} /> Agents
                    </ToggleButton>
                    <ToggleButton value="collections" sx={{ px: 2, minWidth: 140, textTransform: 'none' }}>
                        <ChatIcon sx={{ mr: 0.75, fontSize: 18 }} /> Collections
                    </ToggleButton>
                </ToggleButtonGroup>
            </Box>

            {isLoading ? (
                <Box
                    sx={{
                        display: 'flex',
                        flexDirection: 'column',
                        alignItems: 'center',
                        justifyContent: 'center',
                        minHeight: '300px',
                        textAlign: 'center',
                    }}
                >
                    <Typography variant="h6">
                        Loading collections...
                    </Typography>
                </Box>
            ) : collections.length === 0 ? (
                <Box
                    sx={{
                        display: 'flex',
                        flexDirection: 'column',
                        alignItems: 'center',
                        justifyContent: 'center',
                        minHeight: '300px',
                        textAlign: 'center',
                    }}
                >
                    <Typography variant="h6" gutterBottom>
                        No collections available
                    </Typography>
                    <Typography variant="body2">
                        Collections will appear here when they become available
                    </Typography>
                </Box>
            ) : (
                <Box
                    sx={{
                        display: 'grid',
                        gridTemplateColumns: 'repeat(auto-fill, minmax(240px, 1fr))',
                        gap: 2,
                    }}
                >
                    {collections.map((collection) => (
                        <StyledCard key={collection.id}>
                            <StyledCardActionArea
                                onClick={() => handleCardClick(collection.id)}
                            >
                                <CardContent
                                        className="card-content"
                                        sx={{
                                        p: 2.5,
                                        textAlign: 'left',
                                            flexGrow: 1,
                                            display: 'flex',
                                            flexDirection: 'column',
                                        alignItems: 'flex-start',
                                        }}
                                    >
                                        <IconContainer>
                                            <ChatIcon />
                                        </IconContainer>

                                        <Typography
                                            variant="h6"
                                            component="h2"
                                            gutterBottom
                                            sx={{
                                                fontWeight: 600,
                                                textAlign: 'left',
                                                wordBreak: 'break-word',
                                            }}
                                        >
                                            {collection.name}
                                        </Typography>

                                         <Stack direction="row" spacing={1} sx={{ mt: 'auto', pt: 2 }}>
                                            <Chip
                                                label="Active"
                                                size="small"
                                                color="success"
                                                variant="outlined"
                                            />
                                        </Stack>
                                    </CardContent>
                                </StyledCardActionArea>
                            </StyledCard>
                    ))}
                </Box>
            )}
            </Container>
        </>
    );
}
