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
} from "@mui/material";
import { useRouter } from "next/navigation";
import { styled } from "@mui/material/styles";
import ChatIcon from '@mui/icons-material/Chat';

const StyledCard = styled(Card)(({ theme }) => ({
    height: '100%',
    display: 'flex',
    flexDirection: 'column',
    transition: 'all 0.3s cubic-bezier(0.4, 0, 0.2, 1)',
    cursor: 'pointer',
    '&:hover': {
        transform: 'translateY(-4px)',
        boxShadow: theme.shadows[8],
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
    width: 48,
    height: 48,
    borderRadius: '50%',
    backgroundColor: theme.palette.primary.main,
    color: theme.palette.primary.contrastText,
    marginBottom: theme.spacing(2),
}));

export default function Page() {

    const { isLoading } = useGetCollectionsQuery();
    useGetSessionsQuery();

    const collections = useAppSelector(state => state.chat.collections ?? []);

    const router = useRouter();

    const handleCardClick = (collectionId: string) => {
        router.push(`/chat/${collectionId}`);
    };

    return (
        <Container maxWidth="lg" sx={{ py: 4 }}>
            <Box sx={{ mb: 4 }}>
                <Typography variant="h4" component="h1" gutterBottom fontWeight={600}>
                    Collections
                </Typography>
                <Typography variant="body1">
                    Select a collection to start chatting
                </Typography>
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
                        gridTemplateColumns: {
                            xs: 'repeat(1, 1fr)',
                            sm: 'repeat(2, 1fr)',
                            md: 'repeat(3, 1fr)',
                        },
                        gap: 3,
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
                                            p: 3,
                                            textAlign: 'center',
                                            flexGrow: 1,
                                            display: 'flex',
                                            flexDirection: 'column',
                                            alignItems: 'center',
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
                                                textAlign: 'center',
                                                wordBreak: 'break-word',
                                            }}
                                        >
                                            {collection.name}
                                        </Typography>

                                        <Stack direction="row" spacing={1} sx={{ mt: 2 }}>
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
    );
}