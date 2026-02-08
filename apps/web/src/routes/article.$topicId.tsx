import { createFileRoute } from '@tanstack/react-router';

export const Route = createFileRoute('/article/$topicId')({
  component: ArticlePage,
});

function ArticlePage() {
  const { topicId } = Route.useParams();

  return (
    <div className="p-4">
      <h1 className="text-2xl font-bold">Article View</h1>
      <p className="mt-2 text-gray-600">Topic ID: {topicId}</p>
      <p className="mt-2 text-gray-600">AI-generated article streaming coming soon...</p>
    </div>
  );
}
