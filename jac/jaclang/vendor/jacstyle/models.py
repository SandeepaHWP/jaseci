from dataclasses import dataclass

@dataclass
class DeveloperExceptionConfig:
    pretty_exceptions_enable: bool = True
    pretty_exceptions_show_locals: bool = False
    pretty_exceptions_short: bool = True
