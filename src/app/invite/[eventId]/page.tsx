import { notFound } from 'next/navigation';
import type { Metadata } from 'next';
import { Community } from '@/features/community';
import { isEventId, publicInvite } from '@/lib/public-invite';

export async function generateMetadata({ params }: { params: Promise<{ eventId: string }> }): Promise<Metadata> {
  const { eventId } = await params;
  const invite = await publicInvite(eventId);
  const title = 'koko. — 皇居ゆるランへの招待';
  const description = invite ? `${invite.date} ・ ${invite.zone}集合。アフターカフェは${invite.cafe}。`
    : '皇居で、ゆるく走る仲間を見つけよう。';
  return { title, description, openGraph: { title, description }, twitter: { card: 'summary_large_image', title, description, images: [`/invite/${eventId}/opengraph-image`] } };
}

export default async function Invite({ params }: { params: Promise<{ eventId: string }> }) {
  const { eventId } = await params;
  if (!isEventId(eventId)) notFound();
  return <Community inviteId={eventId} />;
}
