import tkinter as tk
from tkinter import ttk, messagebox
import subprocess
import threading
import queue
import re
import os

REPO = r"C:\NoC_Project"
RUNNER = os.path.join(REPO, "run_noc_demo_test.ps1")

ROUTE_PATTERN = re.compile(
    r"ROUTE TRACE: Router (\d+) --([A-Z]+)--> Router (\d+) at ([\d.]+) ns"
)

class NoCDemo:
    def __init__(self, root):
        self.root = root
        self.root.title("4x4 Mesh NoC — Fault-Aware Routing Demo")
        self.root.geometry("1120x760")
        self.root.minsize(1000, 680)

        self.results = queue.Queue()
        self.running = False

        self.source = tk.StringVar(value="0")
        self.destination = tk.StringVar(value="15")
        self.fault_a = tk.StringVar(value="1")
        self.fault_b = tk.StringVar(value="5")
        self.status = tk.StringVar(value="Ready — configure the network and run a simulation.")

        self.build_ui()
        self.draw_mesh([], None)

        self.root.after(100, self.check_results)

    def build_ui(self):
        title = ttk.Label(
            self.root,
            text="4×4 Mesh Network: Fault-Aware Adaptive Routing",
            font=("Segoe UI", 17, "bold")
        )
        title.pack(pady=(12, 3))

        subtitle = ttk.Label(
            self.root,
            text="Configure a packet and failed link, then run the Vivado simulation."
        )
        subtitle.pack(pady=(0, 10))

        controls = ttk.LabelFrame(self.root, text="Simulation Configuration", padding=10)
        controls.pack(fill="x", padx=12, pady=5)

        router_values = [str(i) for i in range(16)]

        fields = [
            ("Source router", self.source),
            ("Destination router", self.destination),
            ("Fault endpoint A", self.fault_a),
            ("Fault endpoint B", self.fault_b),
        ]

        for col, (label, variable) in enumerate(fields):
            ttk.Label(controls, text=label).grid(
                row=0, column=col, padx=8, pady=(0, 4), sticky="w"
            )
            ttk.Combobox(
                controls,
                textvariable=variable,
                values=router_values,
                state="readonly",
                width=16
            ).grid(row=1, column=col, padx=8, pady=3, sticky="ew")

        for col in range(4):
            controls.columnconfigure(col, weight=1)

        buttons = ttk.Frame(controls)
        buttons.grid(row=2, column=0, columnspan=4, pady=(10, 0))

        self.run_button = ttk.Button(
            buttons, text="Run Vivado Simulation", command=self.run_simulation
        )
        self.run_button.pack(side="left", padx=5)

        ttk.Button(
            buttons, text="Clear Output", command=self.clear_output
        ).pack(side="left", padx=5)

        ttk.Label(
            self.root, textvariable=self.status, anchor="w"
        ).pack(fill="x", padx=16, pady=5)

        content = ttk.Frame(self.root)
        content.pack(fill="both", expand=True, padx=12, pady=5)

        network_frame = ttk.LabelFrame(content, text="4×4 Mesh and Observed Route", padding=5)
        network_frame.pack(side="left", fill="both", expand=True, padx=(0, 6))

        self.canvas = tk.Canvas(
            network_frame, width=540, height=510,
            background="#f8fafc", highlightthickness=0
        )
        self.canvas.pack(fill="both", expand=True)

        log_frame = ttk.LabelFrame(content, text="Vivado Simulation Log", padding=5)
        log_frame.pack(side="left", fill="both", expand=True, padx=(6, 0))

        log_inner = ttk.Frame(log_frame)
        log_inner.pack(fill="both", expand=True)

        self.log = tk.Text(
            log_inner, wrap="word", font=("Consolas", 9),
            background="#111827", foreground="#e5e7eb",
            insertbackground="white", height=25
        )
        scrollbar = ttk.Scrollbar(log_inner, orient="vertical", command=self.log.yview)
        self.log.configure(yscrollcommand=scrollbar.set)

        self.log.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")

        legend = ttk.Label(
            network_frame,
            text="Green = observed route   Blue = source   Orange = destination   Red dashed = failed link"
        )
        legend.pack(fill="x", pady=(4, 0))

    @staticmethod
    def coordinates(router):
        row, col = divmod(router, 4)
        return 55 + col * 140, 55 + row * 130

    @staticmethod
    def adjacent(a, b):
        ra, ca = divmod(a, 4)
        rb, cb = divmod(b, 4)
        return abs(ra - rb) + abs(ca - cb) == 1

    def draw_mesh(self, route, failed_link):
        self.canvas.delete("all")

        # Draw all physical mesh connections.
        for router in range(16):
            x1, y1 = self.coordinates(router)
            row, col = divmod(router, 4)

            if col < 3:
                x2, y2 = self.coordinates(router + 1)
                self.canvas.create_line(
                    x1, y1, x2, y2, fill="#cbd5e1", width=2
                )

            if row < 3:
                x2, y2 = self.coordinates(router + 4)
                self.canvas.create_line(
                    x1, y1, x2, y2, fill="#cbd5e1", width=2
                )

        # Highlight the failed physical link.
        if failed_link:
            a, b = failed_link
            x1, y1 = self.coordinates(a)
            x2, y2 = self.coordinates(b)
            self.canvas.create_line(
                x1, y1, x2, y2, fill="#dc2626", width=5,
                dash=(8, 5)
            )

        # Draw the route observed in the simulation trace.
        for a, b in zip(route, route[1:]):
            x1, y1 = self.coordinates(a)
            x2, y2 = self.coordinates(b)
            self.canvas.create_line(
                x1, y1, x2, y2, fill="#16a34a", width=5,
                arrow=tk.LAST, arrowshape=(12, 15, 5)
            )

        route_set = set(route)
        src = int(self.source.get())
        dst = int(self.destination.get())

        # Draw routers after links so labels remain visible.
        for router in range(16):
            x, y = self.coordinates(router)

            if router == src:
                fill, outline = "#2563eb", "#1d4ed8"
            elif router == dst:
                fill, outline = "#f59e0b", "#d97706"
            elif router in route_set:
                fill, outline = "#bbf7d0", "#16a34a"
            else:
                fill, outline = "#ffffff", "#64748b"

            self.canvas.create_oval(
                x - 21, y - 21, x + 21, y + 21,
                fill=fill, outline=outline, width=2
            )
            text_color = "white" if router in (src, dst) else "#0f172a"
            self.canvas.create_text(
                x, y, text=f"R{router}", fill=text_color,
                font=("Segoe UI", 9, "bold")
            )

    def clear_output(self):
        self.log.delete("1.0", tk.END)
        self.status.set("Output cleared.")
        self.draw_mesh([], None)

    def run_simulation(self):
        if self.running:
            return

        try:
            src = int(self.source.get())
            dst = int(self.destination.get())
            a = int(self.fault_a.get())
            b = int(self.fault_b.get())
        except ValueError:
            messagebox.showerror("Invalid configuration", "Select all four routers.")
            return

        if src == dst:
            messagebox.showerror(
                "Invalid configuration", "Source and destination must differ."
            )
            return

        if a == b or not self.adjacent(a, b):
            messagebox.showerror(
                "Invalid failed link",
                "The two fault endpoints must be distinct, directly connected routers."
            )
            return

        if not os.path.isfile(RUNNER):
            messagebox.showerror("Runner not found", f"Cannot find:\n{RUNNER}")
            return

        self.running = True
        self.run_button.configure(state="disabled")
        self.status.set("Running Vivado compile, elaboration, and simulation...")
        self.log.delete("1.0", tk.END)
        self.log.insert(tk.END, "Starting simulation. Please wait...\n")
        self.draw_mesh([], (a, b))

        threading.Thread(
            target=self.simulation_worker,
            args=(src, dst, a, b),
            daemon=True
        ).start()

    def simulation_worker(self, src, dst, a, b):
        command = [
            "powershell.exe", "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", RUNNER,
            "-Source", str(src),
            "-Destination", str(dst),
            "-FaultA", str(a),
            "-FaultB", str(b)
        ]

        try:
            result = subprocess.run(
                command,
                cwd=REPO,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=240
            )
            self.results.put((result.returncode, result.stdout, (src, dst, a, b)))
        except Exception as exc:
            self.results.put((-1, str(exc), (src, dst, a, b)))

    def check_results(self):
        try:
            while True:
                return_code, output, config = self.results.get_nowait()
                self.finish_simulation(return_code, output, config)
        except queue.Empty:
            pass

        self.root.after(100, self.check_results)

    def finish_simulation(self, return_code, output, config):
        self.running = False
        self.run_button.configure(state="normal")

        src, dst, a, b = config
        self.log.delete("1.0", tk.END)
        self.log.insert(tk.END, output)
        self.log.see(tk.END)

        trace = ROUTE_PATTERN.findall(output)
        route = []

        for start, direction, end, sim_time in trace:
            start, end = int(start), int(end)
            if not route:
                route.append(start)
            if route[-1] == start:
                route.append(end)

        passed = (
            return_code == 0
            and "ALL FAULT REROUTING TESTS PASSED" in output
            and "DEMO SIMULATION PASSED" in output
            and "FAIL:" not in output
        )

        self.draw_mesh(route, (a, b))

        if passed and route and route[-1] == dst:
            self.status.set(
                f"PASS — Route: {' → '.join('R' + str(r) for r in route)}"
                f" | Failed link: R{a}–R{b}"
            )
        elif passed:
            self.status.set(
                "Simulation passed, but the route trace could not be fully reconstructed."
            )
        else:
            self.status.set(
                f"FAILED — inspect the simulation log. Exit code: {return_code}"
            )

if __name__ == "__main__":
    root = tk.Tk()
    app = NoCDemo(root)
    root.mainloop()