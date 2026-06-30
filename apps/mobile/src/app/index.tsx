import type { HealthResponse } from '@lockedin/shared';
import * as Device from 'expo-device';
import { useState } from 'react';
import { Platform, Pressable, StyleSheet } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { AnimatedIcon } from '@/components/animated-icon';
import { HintRow } from '@/components/hint-row';
import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import { WebBadge } from '@/components/web-badge';
import { BottomTabInset, MaxContentWidth, Spacing } from '@/constants/theme';
import { pingHealth } from '@/lib/api';

function getDevMenuHint() {
  if (Platform.OS === 'web') {
    return <ThemedText type="small">use browser devtools</ThemedText>;
  }
  if (Device.isDevice) {
    return (
      <ThemedText type="small">
        shake device or press <ThemedText type="code">m</ThemedText> in terminal
      </ThemedText>
    );
  }
  const shortcut = Platform.OS === 'android' ? 'cmd+m (or ctrl+m)' : 'cmd+d';
  return (
    <ThemedText type="small">
      press <ThemedText type="code">{shortcut}</ThemedText>
    </ThemedText>
  );
}

// Debug card: taps the API's /health endpoint and renders the response after
// validating it through the shared schema. Proves the mobile -> API roundtrip
// and that the type-sharing contract reaches the client (step 8). Temporary —
// gets removed once real screens land.
function HealthCheckCard() {
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
    <ThemedView type="backgroundElement" style={styles.stepContainer}>
      <ThemedText type="smallBold">API roundtrip (debug)</ThemedText>
      <Pressable
        onPress={onPing}
        disabled={loading}
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
      {error && (
        <ThemedText type="small" themeColor="text">
          {`⚠️ ${error}`}
        </ThemedText>
      )}
    </ThemedView>
  );
}

export default function HomeScreen() {
  return (
    <ThemedView style={styles.container}>
      <SafeAreaView style={styles.safeArea}>
        <ThemedView style={styles.heroSection}>
          <AnimatedIcon />
          <ThemedText type="title" style={styles.title}>
            Welcome to&nbsp;Expo
          </ThemedText>
        </ThemedView>

        <ThemedText type="code" style={styles.code}>
          get started
        </ThemedText>

        <ThemedView type="backgroundElement" style={styles.stepContainer}>
          <HintRow
            title="Try editing"
            hint={<ThemedText type="code">src/app/index.tsx</ThemedText>}
          />
          <HintRow title="Dev tools" hint={getDevMenuHint()} />
          <HintRow
            title="Fresh start"
            hint={<ThemedText type="code">npm run reset-project</ThemedText>}
          />
        </ThemedView>

        <HealthCheckCard />

        {Platform.OS === 'web' && <WebBadge />}
      </SafeAreaView>
    </ThemedView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    justifyContent: 'center',
    flexDirection: 'row',
  },
  safeArea: {
    flex: 1,
    paddingHorizontal: Spacing.four,
    alignItems: 'center',
    gap: Spacing.three,
    paddingBottom: BottomTabInset + Spacing.three,
    maxWidth: MaxContentWidth,
  },
  heroSection: {
    alignItems: 'center',
    justifyContent: 'center',
    flex: 1,
    paddingHorizontal: Spacing.four,
    gap: Spacing.four,
  },
  title: {
    textAlign: 'center',
  },
  code: {
    textTransform: 'uppercase',
  },
  stepContainer: {
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
