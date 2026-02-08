import { createFileRoute } from '@tanstack/react-router';

export const Route = createFileRoute('/settings')({
  component: SettingsPage,
});

function SettingsPage() {
  return (
    <div className="p-4">
      <h1 className="text-2xl font-bold">Settings</h1>
      <p className="mt-2 text-gray-600">
        Profile, LLM config, and source management coming soon...
      </p>
    </div>
  );
}
