import { afterEach, describe, expect, it, jest } from '@jest/globals';
import { fireEvent, render } from '@testing-library/react-native';

import { HealthCheckCard } from '@/components/health-check-card';
import { pingHealth } from '@/lib/api';

// Mock the API module so the test exercises the card's own behavior (state +
// rendering), not the network. This also avoids loading the real zod/shared
// chain in the test environment.
jest.mock('@/lib/api');
const mockedPingHealth = jest.mocked(pingHealth);

afterEach(() => {
  jest.clearAllMocks();
});

describe('HealthCheckCard', () => {
  it('renders the validated health response after a successful ping', async () => {
    mockedPingHealth.mockResolvedValue({
      status: 'ok',
      service: 'lockedin-api',
      timestamp: '2026-06-30T00:00:00.000Z',
    });

    const { getByText, findByText } = render(<HealthCheckCard />);
    fireEvent.press(getByText('Ping /health'));

    // Success: the parsed status + service are rendered to the user.
    // findByText throws if the text never appears, so awaiting it is the assertion.
    expect(await findByText(/ok · lockedin-api/)).toBeTruthy();
    expect(mockedPingHealth).toHaveBeenCalledTimes(1);
  });

  it('surfaces the error message when the ping fails', async () => {
    mockedPingHealth.mockRejectedValue(new Error('Health check failed: HTTP 500'));

    const { getByText, findByText } = render(<HealthCheckCard />);
    fireEvent.press(getByText('Ping /health'));

    // Failure: the error is shown on screen, not swallowed.
    expect(await findByText(/Health check failed: HTTP 500/)).toBeTruthy();
  });
});
