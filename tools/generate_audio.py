from math import exp, pi, sin
from pathlib import Path
import random
import struct
import wave


SAMPLE_RATE = 24000
ASSET_DIRECTORY = Path(__file__).resolve().parents[1] / "assets" / "audio"
PROFILES = {
    "pulse": (680.0, 0.14, 0.10),
    "vector": (260.0, 0.32, 0.08),
    "classic": (150.0, 0.58, 0.12),
}


def shot_samples(frequency: float, noise_mix: float, seed: int) -> list[float]:
    generator = random.Random(seed)
    samples = []
    phase_rad = 0.0
    duration_s = 0.075
    for sample_index in range(round(duration_s * SAMPLE_RATE)):
        time_s = sample_index / SAMPLE_RATE
        phase_rad += 2.0 * pi * frequency * exp(-time_s * 24.0) / SAMPLE_RATE
        attack = min(time_s / 0.0008, 1.0)
        release = min((duration_s - time_s) / 0.008, 1.0)
        tone = sin(phase_rad) * (1.0 - noise_mix)
        noise = generator.uniform(-1.0, 1.0) * noise_mix * exp(-time_s * 50.0)
        samples.append((tone + noise) * exp(-time_s * 60.0) * attack * release * 0.65)
    return samples


def write_wave(path: Path, samples: list[float]) -> None:
    with wave.open(str(path), "wb") as stream:
        stream.setnchannels(1)
        stream.setsampwidth(2)
        stream.setframerate(SAMPLE_RATE)
        stream.writeframes(b"".join(struct.pack("<h", round(max(-1.0, min(1.0, sample)) * 32767)) for sample in samples))


def main() -> None:
    ASSET_DIRECTORY.mkdir(parents=True, exist_ok=True)
    for profile_index, (profile_id, parameters) in enumerate(PROFILES.items()):
        frequency, noise_mix, interval_s = parameters
        samples = shot_samples(frequency, noise_mix, profile_index + 42)
        write_wave(ASSET_DIRECTORY / f"{profile_id}_shot.wav", samples)
        loop = [0.0] * round(4.0 * interval_s * SAMPLE_RATE)
        for pulse_index in range(4):
            start_index = round(pulse_index * interval_s * SAMPLE_RATE)
            for sample_index, sample in enumerate(samples):
                loop[start_index + sample_index] += sample * 0.72
        write_wave(ASSET_DIRECTORY / f"{profile_id}_continuous.wav", loop)
    print("6 sons originaux générés : PCM mono 16 bits, 24 kHz, sans dépendance externe.")


if __name__ == "__main__":
    main()
