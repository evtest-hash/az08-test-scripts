import os
import sys
import subprocess
import time
import numpy as np
import wave

def log(level, msg):
    ts = time.strftime('%Y-%m-%d %H:%M:%S')
    print(f"[{ts}] [{os.getpid()}] [{level}] {msg}")

def generate_sine_wav(filename, duration, sr, ch, freq):
    log("INFO", f"Generating {duration}s {sr}Hz {('mono' if ch==1 else 'stereo')} {freq}Hz sine wave using numpy...")
    t = np.linspace(0, duration, int(sr * duration), endpoint=False)
    sine_wave = np.sin(2 * np.pi * freq * t) 
    audio = np.int16(sine_wave * 32767)
    if ch == 2:
        audio = np.column_stack((audio, audio))
    with wave.open(filename, 'wb') as wf:
        wf.setnchannels(ch)
        wf.setsampwidth(2)  
        wf.setframerate(sr)
        if ch == 1:
            wf.writeframes(audio.tobytes())
        else:
            wf.writeframes(audio.flatten().tobytes())

def record_wav(filename, duration, sr, ch):
    log("INFO", f"Recording to {filename}...")
    cmd = [
        "arecord", "-f", "S16_LE", "-r", str(sr), "-c", str(ch),
        "-t", "wav", "-d", str(duration), filename
    ]
    proc = subprocess.Popen(cmd)
    return proc

def set_amixer_controls():
    amixer_cmds = [
        ["amixer", "-c", "0", "sset", "Left Line Mux", "Line 1L"],
        ["amixer", "-c", "0", "sset", "Right Line Mux", "Line 1R"],
        ["amixer", "-c", "0", "sset", "Left PGA Mux", "Line 1L"],
        ["amixer", "-c", "0", "sset", "Right PGA Mux", "Line 1R"],
        ["amixer", "-c", "0", "sset", "Mono Mux", "Stereo"],
        ["amixer", "-c", "0", "sset", "Left Channel", "0"],
        ["amixer", "-c", "0", "sset", "Right Channel", "0"],
        ["amixer", "-c", "0", "sset", "Output 1", "30"],
        ["amixer", "-c", "0", "sset", "Output 2", "30"],
    ]
    for cmd in amixer_cmds:
        try:
            subprocess.run(cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            log("INFO", f"Ran: {' '.join(cmd)}")
        except subprocess.CalledProcessError as e:
            log("ERROR", f"Failed to run: {' '.join(cmd)}; {e}")

def play_wav(filename):
    set_amixer_controls()
    log("INFO", "Playing sine wave...")
    cmd = ["aplay", filename]
    try:
        subprocess.run(cmd, check=True)
    except subprocess.CalledProcessError:
        log("ERROR", "Playback failed.")
        return False
    return True

def read_wav_np(filename):
    with wave.open(filename, 'rb') as wf:
        n_channels = wf.getnchannels()
        sample_width = wf.getsampwidth()
        sample_rate = wf.getframerate()
        n_frames = wf.getnframes()
        frames = wf.readframes(n_frames)
        if sample_width != 2:
            raise ValueError("Only 16-bit PCM WAV files are supported")
        data = np.frombuffer(frames, dtype=np.int16)
        if n_channels > 1:
            data = data.reshape(-1, n_channels)
        return sample_rate, data

def get_main_freq(wav_file):
    if not os.path.exists(wav_file):
        log("ERROR", f"File '{wav_file}' not found.")
        return "unknown"
    try:
        sample_rate, data = read_wav_np(wav_file)
    except Exception as e:
        log("ERROR", f"Error reading WAV file: {e}")
        return "unknown"
    if len(data.shape) == 2:
        data = data[:, 0]
        log("INFO", "Stereo detected, using left channel.")
    data = data.astype(np.float32)
    data = data - np.mean(data)

    window = np.ones_like(data)
    windowed_data = data * window

    fft_result = np.fft.rfft(windowed_data)
    fft_magnitude = np.abs(fft_result)
    freqs = np.fft.rfftfreq(len(windowed_data), d=1.0 / sample_rate)
    main_idx = np.argmax(fft_magnitude)
    main_freq = freqs[main_idx]
    log("INFO", f"Main frequency in {wav_file}: {main_freq:.2f} Hz")
    return f"{main_freq:.2f}"

def run_test_once(DURATION, SR, CH, FREQ, SINE_FILE, REC_FILE):
    # Clean up old files
    log("INFO", "Cleaning up old WAV and temp files...")
    for f in [SINE_FILE, REC_FILE]:
        try:
            os.remove(f)
        except FileNotFoundError:
            pass

    # Generate sine wave
    generate_sine_wav(SINE_FILE, DURATION, SR, CH, FREQ)

    # Start recording
    rec_proc = record_wav(REC_FILE, DURATION, SR, CH)
    

    # Play sine wave
    if not play_wav(SINE_FILE):
        rec_proc.terminate()
        rec_proc.wait()
        return "unknown", "unknown", False

    # Wait for recording to finish
    rec_proc.wait()
    if rec_proc.returncode != 0:
        log("ERROR", "Recording process exited abnormally.")
        return "unknown", "unknown", False

    # Analyze generated file
    log("INFO", "Analyzing generated file frequency...")
    FREQ_SINE = get_main_freq(SINE_FILE)
    log("INFO", f"Generated file main frequency: {FREQ_SINE} Hz (expected: {FREQ} Hz)")

    # Analyze recorded file
    log("INFO", "Analyzing recorded file frequency...")
    FREQ_REC = get_main_freq(REC_FILE)
    log("INFO", f"Recorded file main frequency: {FREQ_REC} Hz (expected: {FREQ} Hz)")

    # Only compare the main frequencies, must match exactly (as string)
    if FREQ_SINE == "unknown" or FREQ_REC == "unknown":
        log("ERROR", "Frequency detection failed.")
        return FREQ_SINE, FREQ_REC, False
    elif FREQ_SINE == FREQ_REC:
        log("INFO", "Frequencies match exactly. Test PASSED.")
        return FREQ_SINE, FREQ_REC, True
    else:
        log("ERROR", "Frequencies do not match. Test FAILED.")
        return FREQ_SINE, FREQ_REC, False

def main():
    DURATION = 2
    SR = 48000
    CH = 2
    FREQ = 1000
    SINE_FILE = "sine_mono.wav"
    REC_FILE = "recorded_mono.wav"

    max_attempts = 3
    attempt = 0
    passed = False
    last_freq_sine = "unknown"
    last_freq_rec = "unknown"

    while attempt < max_attempts:
        log("INFO", f"Test attempt {attempt+1} of {max_attempts}...")
        freq_sine, freq_rec, result = run_test_once(DURATION, SR, CH, FREQ, SINE_FILE, REC_FILE)
        last_freq_sine = freq_sine
        last_freq_rec = freq_rec
        if result:
            passed = True
            break
        attempt += 1
        if attempt < max_attempts:
            log("INFO", "Retrying test...")

    print()
    print("Result comparison:")
    print(f"  {'File':<24} {'Main Frequency (Hz)':<20}")
    print(f"  {'sine_mono.wav':<24} {last_freq_sine:<20}")
    print(f"  {'recorded_mono.wav':<24} {last_freq_rec:<20}")
    if passed:
        log("INFO", f"Test PASSED in {attempt+1} attempt(s).")
        log("INFO", "Test completed.")
        sys.exit(0)
    else:
        log("ERROR", f"Test FAILED after {max_attempts} attempts.")
        log("INFO", "Test completed.")
        sys.exit(1)

if __name__ == "__main__":
    main()
