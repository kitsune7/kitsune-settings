# Vibe Compilers

## What are Vibe Compilers?

Vibe Compilers are specialized markdown-based files (with the `.vc` extension) designed to guide AI systems in
generating code according to specific guidelines, styles, or workflows. Each Vibe Compiler encapsulates a set of
instructions, constraints, and best practices tailored for a particular coding context or behavioral approach. When a
Vibe Compiler is pulled into context, it shapes the AI's responses and code generation to align with the intended "vibe"
—- whether that's a teaching style, a coding philosophy, or a domain-specific approach.

Importantly, Vibe Compilers are not meant to define the AI's persona. Instead, they are designed to be added to existing
personas, providing behavioral instructions and coding guidelines that influence how the AI operates within a given
context. This separation allows for flexible, modular customization of AI behavior without altering the underlying
persona.

In addition to `.vc` files, the system supports `.jmp` files ("just more prompt"), which are modular prompt extensions
that can be pulled into context to further refine or extend the behavior and instructions provided by a Vibe Compiler.
Both `.vc` and `.jmp` files can be combined or layered to suit different coding scenarios, making them powerful tools
for customizing the AI-driven coding experience.

These compilers are not standalone code generators; instead, they act as prompt blueprints that influence how new code
is created in a separate, user-specified file or project. By leveraging Vibe Compilers and prompt extensions, users can
ensure consistency, maintain standards, and foster creativity within defined boundaries, all while benefiting from the
flexibility of AI-assisted development.

Vibe Compilers are modular and can be combined or extended to suit different coding scenarios. They are meant to be
easily pulled into context as needed, making them a powerful tool for anyone looking to customize their AI-driven coding
experience.

This concept was pioneered by [InvaderSquibs](https://github.com/InvaderSquibs).
