import type { HealthResponse } from '@lockedin/shared';
import { useState } from 'react';
import { Pressable, StyleSheet } from 'react-native';

import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import { Spacing } from '@/constants/theme';
import { pingHealth } from '@/lib/api';

// Debug card: taps the API's /health endpoint and renders the response after
// validating it through the shared schema. Proves the mobile -> API roundtrip
// and that the type-sharing contract reaches the client (step 8). Temporary —
// gets removed once real screens land.
export function HealthCheckCard() {
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState<HealthResponse | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function onPing() {
    setLoading(true);
    setError(null);
    setResult(null);
    try {
      setResult(await pingHealth());
    } catch (err) {
      // Surface the failure on-screen instead of swallowing it.
      setError(err instanceof Error ? err.message : 'Unknown error');
    } finally {
      setLoading(false);
    }
  }

  return (
    <ThemedView type="backgroundElement" style={styles.card}>
      <ThemedText type="smallBold">API roundtrip (debug)</ThemedText>
      <Pressable
        onPress={onPing}
        disabled={loading}
        accessibilityRole="button"
        style={[styles.button, loading && styles.buttonDisabled]}>
        <ThemedText type="smallBold" style={styles.buttonText}>
          {loading ? 'Pinging…' : 'Ping /health'}
        </ThemedText>
      </Pressable>
      {result && (
        <ThemedText type="code">
          {`✅ ${result.status} · ${result.service}\n${result.timestamp}`}
        </ThemedText>
      )}
      {error && <ThemedText type="small">{`⚠️ ${error}`}</ThemedText>}
    </ThemedView>
  );
}

const styles = StyleSheet.create({
  card: {
    gap: Spacing.three,
    alignSelf: 'stretch',
    paddingHorizontal: Spacing.three,
    paddingVertical: Spacing.four,
    borderRadius: Spacing.four,
  },
  button: {
    backgroundColor: '#208AEF',
    paddingVertical: Spacing.two,
    paddingHorizontal: Spacing.three,
    borderRadius: Spacing.two,
    alignItems: 'center',
  },
  buttonDisabled: {
    opacity: 0.5,
  },
  buttonText: {
    color: '#ffffff',
  },
});
