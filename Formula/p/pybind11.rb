class Pybind11 < Formula
  desc "Seamless operability between C++11 and Python"
  homepage "https://github.com/pybind/pybind11"
  url "https://github.com/pybind/pybind11/archive/refs/tags/v2.13.5.tar.gz"
  sha256 "b1e209c42b3a9ed74da3e0b25a4f4cd478d89d5efbb48f04b277df427faf6252"
  license "BSD-3-Clause"

  livecheck do
    url :stable
    regex(/^v?(\d+(?:\.\d+)+)$/i)
  end

  bottle do
    sha256 cellar: :any_skip_relocation, arm64_sonoma:   "32db552c7241a9a94ecb052c054a5da1a8e4bf2095ec621f52b90a4a366acef5"
    sha256 cellar: :any_skip_relocation, arm64_ventura:  "32db552c7241a9a94ecb052c054a5da1a8e4bf2095ec621f52b90a4a366acef5"
    sha256 cellar: :any_skip_relocation, arm64_monterey: "32db552c7241a9a94ecb052c054a5da1a8e4bf2095ec621f52b90a4a366acef5"
    sha256 cellar: :any_skip_relocation, sonoma:         "f20f6f224a7d18ea56c93b6e8ee9eebcea956d5a471190a3bd790f83aedbfee2"
    sha256 cellar: :any_skip_relocation, ventura:        "f20f6f224a7d18ea56c93b6e8ee9eebcea956d5a471190a3bd790f83aedbfee2"
    sha256 cellar: :any_skip_relocation, monterey:       "f20f6f224a7d18ea56c93b6e8ee9eebcea956d5a471190a3bd790f83aedbfee2"
    sha256 cellar: :any_skip_relocation, x86_64_linux:   "32db552c7241a9a94ecb052c054a5da1a8e4bf2095ec621f52b90a4a366acef5"
  end

  depends_on "cmake" => :build
  depends_on "python-setuptools" => :build
  depends_on "python@3.11" => [:build, :test]
  depends_on "python@3.12" => [:build, :test]

  def pythons
    deps.map(&:to_formula)
        .select { |f| f.name.match?(/^python@3\.\d+$/) }
  end

  def install
    # Install /include and /share/cmake to the global location
    system "cmake", "-S", ".", "-B", "build", "-DPYBIND11_TEST=OFF", "-DPYBIND11_NOPYTHON=ON", *std_cmake_args
    system "cmake", "--install", "build"

    pythons.each do |python|
      # Install Python package too
      python_exe = python.opt_libexec/"bin/python"
      system python_exe, "-m", "pip", "install", *std_pip_args(prefix: libexec), "."

      site_packages = Language::Python.site_packages(python_exe)
      pth_contents = "import site; site.addsitedir('#{libexec/site_packages}')\n"
      (prefix/site_packages/"homebrew-pybind11.pth").write pth_contents

      pyversion = Language::Python.major_minor_version(python_exe)
      bin.install libexec/"bin/pybind11-config" => "pybind11-config-#{pyversion}"

      next if python != pythons.max_by(&:version)

      # The newest one is used as the default
      bin.install_symlink "pybind11-config-#{pyversion}" => "pybind11-config"
    end
  end

  test do
    (testpath/"example.cpp").write <<~EOS
      #include <pybind11/pybind11.h>

      int add(int i, int j) {
          return i + j;
      }
      namespace py = pybind11;
      PYBIND11_MODULE(example, m) {
          m.doc() = "pybind11 example plugin";
          m.def("add", &add, "A function which adds two numbers");
      }
    EOS

    (testpath/"example.py").write <<~EOS
      import example
      example.add(1,2)
    EOS

    pythons.each do |python|
      python_exe = python.opt_libexec/"bin/python"
      pyversion = Language::Python.major_minor_version(python_exe)
      site_packages = Language::Python.site_packages(python_exe)

      python_flags = Utils.safe_popen_read(
        python.opt_libexec/"bin/python-config",
        "--cflags",
        "--ldflags",
        "--embed",
      ).split
      system ENV.cxx, "-shared", "-fPIC", "-O3", "-std=c++11", "example.cpp", "-o", "example.so", *python_flags
      system python_exe, "example.py"

      test_module = shell_output("#{python_exe} -m pybind11 --includes")
      assert_match (libexec/site_packages).to_s, test_module

      test_script = shell_output("#{bin}/pybind11-config-#{pyversion} --includes")
      assert_match test_module, test_script

      next if python != pythons.max_by(&:version)

      test_module = shell_output("#{python_exe} -m pybind11 --includes")
      test_script = shell_output("#{bin}/pybind11-config --includes")
      assert_match test_module, test_script
    end
  end
end
