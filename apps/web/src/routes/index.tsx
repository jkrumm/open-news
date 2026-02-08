import { createFileRoute } from '@tanstack/react-router';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';

export const Route = createFileRoute('/')({
  component: FeedPage,
});

function FeedPage() {
  return (
    <div className="p-8 space-y-8">
      <div>
        <h1 className="text-3xl font-bold">OpenNews Feed</h1>
        <p className="mt-2 text-muted-foreground">Daily personalized news feed coming soon...</p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>ShadCN/ui + BasaltUI Setup</CardTitle>
          <CardDescription>Components are now installed and themed with BasaltUI</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="space-y-2">
            <label htmlFor="test-input" className="text-sm font-medium">
              Test Input
            </label>
            <Input id="test-input" placeholder="Type something..." />
          </div>

          <div className="flex gap-2">
            <Button>Primary Button</Button>
            <Button variant="secondary">Secondary</Button>
            <Button variant="outline">Outline</Button>
            <Dialog>
              <DialogTrigger asChild>
                <Button variant="default">Open Dialog</Button>
              </DialogTrigger>
              <DialogContent>
                <DialogHeader>
                  <DialogTitle>Test Dialog</DialogTitle>
                  <DialogDescription>
                    This is a test dialog to verify component theming.
                  </DialogDescription>
                </DialogHeader>
                <p>Dialog content goes here.</p>
              </DialogContent>
            </Dialog>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
