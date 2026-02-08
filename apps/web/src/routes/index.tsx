import { createFileRoute } from '@tanstack/react-router';

export const Route = createFileRoute('/')({
  component: FeedPage,
});

function FeedPage() {
  return (
    <div className="p-4">
      <h1 className="text-2xl font-bold">OpenNews Feed</h1>
      <p className="mt-2 text-gray-600">Daily personalized news feed coming soon...</p>
    </div>
  );
}
