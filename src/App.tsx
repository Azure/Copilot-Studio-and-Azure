import { motion, useScroll, useTransform } from 'framer-motion'
import { ArrowRight, GithubLogo, Sparkle, Lightning, Target, Database, Brain, Gear, FileText, Flask, Tree, ShieldCheck, Rocket, Check, Chat, Envelope, Globe, Phone, MicrosoftTeamsLogo, VideoCamera, Users, Cube } from '@phosphor-icons/react'
import { Button } from '@/components/ui/button'
import { useRef } from 'react'

const REPO_URL = 'https://github.com/Azure/Copilot-Studio-and-Azure'

const whatFeatures = [
  {
    icon: Gear,
    title: 'Copilot Studio',
    description: 'A graphical, low-code tool for building AI agents and agent flows with enterprise-grade capabilities.',
  },
  {
    icon: Brain,
    title: 'Foundry IQ',
    description: 'Microsoft\'s unified knowledge layer with agentic retrieval—36% better response relevance than traditional RAG.',
  },
  {
    icon: Database,
    title: 'Azure AI Integration',
    description: 'Full Azure AI potential: custom models, AI Search, and advanced RAG implementations for tailored solutions.',
  }
]

const whyFeatures = [
  {
    title: 'Rapid Prototyping + Deep Customization',
    description: 'Build fast with low-code, then extend with Azure AI for production-grade intelligence.',
  },
  {
    title: 'Unified Knowledge Access',
    description: 'Query across multiple specialized knowledge bases simultaneously with automatic intelligent routing.',
  },
  {
    title: 'Tailored AI Solutions',
    description: 'Use fine-tuned models for specific use cases, delivering context-aware and highly relevant outcomes.',
  },
  {
    title: 'Native Microsoft 365 Integration',
    description: 'Seamlessly integrate with the Microsoft ecosystem your enterprise already relies on.',
  }
]

const whenScenarios = [
  'Out-of-the-box Copilot Studio capabilities aren\'t enough',
  'You need highly accurate AI responses for specific requirements',
  'Complex databases demand deep customization',
  'You need to query multiple knowledge sources simultaneously',
  'Deep expertise is required on demand with grounded, cited responses',
  'You have access to thousands of high-quality examples and verified data'
]

const useCases = [
  {
    icon: ShieldCheck,
    title: 'Healthcare',
    description: 'Doctors instantly find clinical guidelines and patient records, improving diagnosis and care quality.',
    link: `${REPO_URL}#usage-scenarios`
  },
  {
    icon: Flask,
    title: 'Financial Services',
    description: 'Compliance teams search regulatory documents and audit trails for fast, accurate legal query responses.',
    link: `${REPO_URL}#usage-scenarios`
  },
  {
    icon: Tree,
    title: 'Fraud Investigation',
    description: '80% reduction in research time and 60% improvement in fraud detection accuracy with Foundry IQ.',
    link: `${REPO_URL}#usage-scenarios`
  }
]

const accelerators = [
  {
    title: 'Content Flow',
    description: 'High-accuracy RAG with automated document ingestion, intelligent chunking, and multimodal retrieval.',
    link: `${REPO_URL}#solutions-accelerators`
  },
  {
    title: 'AI Search Flow',
    description: 'Interact with Azure AI Search through manual triggers for indexing, uploads, and semantic queries.',
    link: `${REPO_URL}#solutions-accelerators`
  },
  {
    title: 'Video RAG Accelerator',
    description: 'Intelligent Q&A over training videos with automatic extraction and structured knowledge transformation.',
    link: `${REPO_URL}#solutions-accelerators`
  }
]

const stats = [
  { icon: Brain, label: 'Better response relevance' },
  { icon: Lightning, label: 'Reduction in research time' },
  { icon: Target, label: 'Improve accuracy' },
  { icon: Database, label: 'Multi-source knowledge bases' }
]

function App() {
  const heroRef = useRef(null)
  const { scrollYProgress } = useScroll({
    target: heroRef,
    offset: ["start start", "end start"]
  })
  
  const opacity = useTransform(scrollYProgress, [0, 0.5], [1, 0])
  const scale = useTransform(scrollYProgress, [0, 0.5], [1, 0.95])

  return (
    <div className="min-h-screen bg-background overflow-x-hidden">
      <nav className="fixed top-6 left-1/2 -translate-x-1/2 z-50 w-[90%] max-w-[1200px]">
        <motion.div 
          initial={{ opacity: 0, y: -20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6 }}
          className="bg-background/30 backdrop-blur-md border border-border/50 rounded-full px-6 lg:px-8 h-[64px] flex items-center justify-between shadow-lg shadow-black/5"
        >
          <motion.div 
            initial={{ opacity: 0, x: -20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ duration: 0.5, delay: 0.1 }}
            className="flex items-center gap-2"
          >
            <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-accent to-accent/60 flex items-center justify-center">
              <Sparkle weight="fill" className="text-white" size={18} />
            </div>
            <span className="font-semibold text-[15px] tracking-tight">Copilot Studio + Azure</span>
          </motion.div>
          
          <motion.div
            initial={{ opacity: 0, x: 20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ duration: 0.5, delay: 0.1 }}
          >
            <Button 
              variant="ghost" 
              size="sm" 
              className="text-[15px] font-medium hover:bg-secondary/80 transition-all duration-300 rounded-full"
              asChild
            >
              <a href={REPO_URL} target="_blank" rel="noopener noreferrer" className="flex items-center gap-2">
                <GithubLogo weight="fill" size={18} />
                <span className="hidden sm:inline">GitHub</span>
              </a>
            </Button>
          </motion.div>
        </motion.div>
      </nav>
      <main>
        <section ref={heroRef} className="relative min-h-screen flex items-center justify-center pt-[100px] px-6">
          <motion.div 
            style={{ opacity, scale }}
            className="max-w-[1000px] mx-auto text-center space-y-8 py-20 md:py-32"
          >
            <motion.div
              initial={{ opacity: 0, y: 30 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.8, delay: 0.2 }}
            >
              <h1 className="text-[56px] sm:text-[72px] md:text-[88px] lg:text-[104px] font-semibold tracking-[-0.04em] leading-[0.95] text-foreground">
                Build intelligent
                <br />
                <span className="bg-gradient-to-r from-accent via-accent/80 to-accent bg-clip-text text-transparent">AI agents</span>
                {' '}with Azure
              </h1>
            </motion.div>

            <motion.p
              initial={{ opacity: 0, y: 30 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.8, delay: 0.4 }}
              className="text-[20px] md:text-[24px] text-muted-foreground max-w-[700px] mx-auto leading-relaxed font-light"
            >
              Rapidly build and deploy enterprise-grade copilots using low-code Copilot Studio integrated with Azure AI for secure, scalable, and intelligent workflows.
            </motion.p>

            <motion.div
              initial={{ opacity: 0, y: 30 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.8, delay: 0.6 }}
              className="flex flex-col sm:flex-row items-center justify-center gap-4 pt-8"
            >
              <Button 
                size="lg" 
                className="bg-foreground hover:bg-foreground/90 text-background px-8 h-[56px] text-[17px] font-medium rounded-full transition-all duration-300 hover:scale-[1.02] hover:shadow-xl"
                asChild
              >
                <a href={REPO_URL} target="_blank" rel="noopener noreferrer" className="flex items-center gap-2">
                  View repository
                  <ArrowRight weight="bold" size={20} />
                </a>
              </Button>
            </motion.div>
          </motion.div>
        </section>

        <section className="py-24 md:py-32 bg-muted/30">
          <div className="max-w-[1400px] mx-auto px-6 lg:px-12">
            <div className="grid grid-cols-2 md:grid-cols-4 gap-8 md:gap-12">
              {stats.map((stat, index) => (
                <motion.div
                  key={stat.label}
                  initial={{ opacity: 0, y: 20 }}
                  whileInView={{ opacity: 1, y: 0 }}
                  viewport={{ once: true }}
                  transition={{ duration: 0.5, delay: index * 0.1 }}
                  className="text-center space-y-3"
                >
                  <div className="inline-flex p-3 rounded-2xl bg-background border border-border">
                    <stat.icon weight="duotone" size={28} className="text-accent" />
                  </div>
                  <div className="text-[16px] text-foreground font-medium">{stat.label}</div>
                </motion.div>
              ))}
            </div>
          </div>
        </section>

        <section id="what" className="py-32 md:py-40">
          <div className="max-w-[1400px] mx-auto px-6 lg:px-12">
            <motion.div
              initial={{ opacity: 0, y: 30 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ duration: 0.7 }}
              className="text-center space-y-6 mb-20 md:mb-28 max-w-[800px] mx-auto"
            >
              <h2 className="text-[48px] md:text-[64px] font-semibold tracking-[-0.03em] leading-tight">
                What it is
              </h2>
              <p className="text-[20px] md:text-[22px] text-muted-foreground leading-relaxed font-light">
                Microsoft's most advanced AI technologies working in harmony to create intelligent, knowledge-grounded agents
              </p>
            </motion.div>

            <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
              {whatFeatures.map((feature, index) => (
                <motion.div
                  key={feature.title}
                  initial={{ opacity: 0, y: 30 }}
                  whileInView={{ opacity: 1, y: 0 }}
                  viewport={{ once: true }}
                  transition={{ duration: 0.5, delay: index * 0.1 }}
                  className="p-10 rounded-3xl bg-card border border-border text-center space-y-6"
                >
                  <div className="inline-flex p-4 rounded-2xl bg-accent/10">
                    <feature.icon weight="duotone" size={40} className="text-accent" />
                  </div>
                  <div className="space-y-4">
                    <h3 className="text-[24px] font-semibold tracking-tight">
                      {feature.title}
                    </h3>
                    <p className="text-[17px] text-muted-foreground leading-relaxed font-light">
                      {feature.description}
                    </p>
                  </div>
                </motion.div>
              ))}
            </div>
          </div>
        </section>

        <section id="why" className="py-32 md:py-40 bg-muted/30">
          <div className="max-w-[1400px] mx-auto px-6 lg:px-12">
            <motion.div
              initial={{ opacity: 0, y: 30 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ duration: 0.7 }}
              className="text-center space-y-6 mb-20 md:mb-28 max-w-[800px] mx-auto"
            >
              <h2 className="text-[48px] md:text-[64px] font-semibold tracking-[-0.03em] leading-tight">
                Why use it
              </h2>
              <p className="text-[20px] md:text-[22px] text-muted-foreground leading-relaxed font-light">
                Go beyond out-of-the-box capabilities with optimized RAG, fine-tuning, and multi-source knowledge access
              </p>
            </motion.div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              {whyFeatures.map((feature, index) => (
                <motion.div
                  key={feature.title}
                  initial={{ opacity: 0, y: 30 }}
                  whileInView={{ opacity: 1, y: 0 }}
                  viewport={{ once: true }}
                  transition={{ duration: 0.5, delay: index * 0.1 }}
                  className="p-10 rounded-3xl bg-card border border-border space-y-4"
                >
                  <h3 className="text-[24px] font-semibold tracking-tight">
                    {feature.title}
                  </h3>
                  <p className="text-[17px] text-muted-foreground leading-relaxed font-light">
                    {feature.description}
                  </p>
                </motion.div>
              ))}
            </div>
          </div>
        </section>

        <section id="when" className="py-32 md:py-40">
          <div className="max-w-[1400px] mx-auto px-6 lg:px-12">
            <motion.div
              initial={{ opacity: 0, y: 30 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ duration: 0.7 }}
              className="text-center space-y-6 mb-20 md:mb-28 max-w-[800px] mx-auto"
            >
              <h2 className="text-[48px] md:text-[64px] font-semibold tracking-[-0.03em] leading-tight">
                When to use it
              </h2>
              <p className="text-[20px] md:text-[22px] text-muted-foreground leading-relaxed font-light">
                Copilot Studio empowered by Azure is recommended when you need to go beyond the basics
              </p>
            </motion.div>

            <div className="max-w-[900px] mx-auto space-y-4">
              {whenScenarios.map((scenario, index) => (
                <motion.div
                  key={index}
                  initial={{ opacity: 0, x: -30 }}
                  whileInView={{ opacity: 1, x: 0 }}
                  viewport={{ once: true }}
                  transition={{ duration: 0.5, delay: index * 0.1 }}
                  className="p-6 rounded-2xl bg-card border border-border flex items-start gap-4"
                >
                  <div className="flex-shrink-0 w-6 h-6 rounded-full bg-accent/10 flex items-center justify-center mt-1">
                    <Check weight="bold" size={14} className="text-accent" />
                  </div>
                  <p className="text-[18px] text-foreground leading-relaxed">
                    {scenario}
                  </p>
                </motion.div>
              ))}
            </div>
          </div>
        </section>

        <section id="architecture" className="py-32 md:py-40 bg-muted/30">
          <div className="max-w-[1400px] mx-auto px-6 lg:px-12">
            <motion.div
              initial={{ opacity: 0, y: 30 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ duration: 0.7 }}
              className="text-center space-y-6 mb-20 md:mb-28 max-w-[800px] mx-auto"
            >
              <h2 className="text-[48px] md:text-[64px] font-semibold tracking-[-0.03em] leading-tight">
                Architecture
              </h2>
              <p className="text-[20px] md:text-[22px] text-muted-foreground leading-relaxed font-light">
                A comprehensive system architecture integrating Copilot Studio with Azure AI capabilities
              </p>
            </motion.div>

            <div className="grid grid-cols-1 lg:grid-cols-12 gap-8">
              <motion.div
                initial={{ opacity: 0, x: -30 }}
                whileInView={{ opacity: 1, x: 0 }}
                viewport={{ once: true }}
                transition={{ duration: 0.6 }}
                className="lg:col-span-8"
              >
                <div className="p-8 lg:p-12 rounded-3xl bg-gradient-to-br from-card to-card/50 border border-border/50 space-y-8">
                  <div className="space-y-6">
                    <div className="flex items-center gap-3 pb-4 border-b border-border/50">
                      <div className="p-2 rounded-xl bg-gradient-to-br from-accent/20 to-accent/10">
                        <Sparkle weight="duotone" size={24} className="text-accent" />
                      </div>
                      <h3 className="text-[20px] font-semibold">Copilot Studio Orchestrator</h3>
                    </div>

                    <div className="grid grid-cols-2 gap-4">
                      <div className="p-5 rounded-2xl bg-background/60 border border-border/50 space-y-3">
                        <div className="flex items-center gap-3">
                          <Users weight="duotone" size={20} className="text-accent" />
                          <span className="text-[14px] font-semibold">Channels</span>
                        </div>
                        <div className="grid grid-cols-3 gap-2">
                          <div className="flex flex-col items-center gap-2 p-2 rounded-lg bg-secondary/30">
                            <Chat weight="duotone" size={18} className="text-accent" />
                            <span className="text-[10px] text-muted-foreground">Copilot</span>
                          </div>
                          <div className="flex flex-col items-center gap-2 p-2 rounded-lg bg-secondary/30">
                            <MicrosoftTeamsLogo weight="duotone" size={18} className="text-accent" />
                            <span className="text-[10px] text-muted-foreground">Teams</span>
                          </div>
                          <div className="flex flex-col items-center gap-2 p-2 rounded-lg bg-secondary/30">
                            <Envelope weight="duotone" size={18} className="text-accent" />
                            <span className="text-[10px] text-muted-foreground">Email</span>
                          </div>
                          <div className="flex flex-col items-center gap-2 p-2 rounded-lg bg-secondary/30">
                            <Phone weight="duotone" size={18} className="text-accent" />
                            <span className="text-[10px] text-muted-foreground">Voice</span>
                          </div>
                          <div className="flex flex-col items-center gap-2 p-2 rounded-lg bg-secondary/30">
                            <VideoCamera weight="duotone" size={18} className="text-accent" />
                            <span className="text-[10px] text-muted-foreground">Web</span>
                          </div>
                          <div className="flex flex-col items-center gap-2 p-2 rounded-lg bg-secondary/30">
                            <Users weight="duotone" size={18} className="text-accent" />
                            <span className="text-[10px] text-muted-foreground">Social</span>
                          </div>
                        </div>
                      </div>

                      <div className="p-5 rounded-2xl bg-background/60 border border-border/50 space-y-3">
                        <div className="flex items-center gap-3">
                          <Database weight="duotone" size={20} className="text-accent" />
                          <span className="text-[14px] font-semibold">Knowledge</span>
                        </div>
                        <div className="grid grid-cols-3 gap-2">
                          <div className="flex flex-col items-center gap-2 p-2 rounded-lg bg-secondary/30">
                            <Globe weight="duotone" size={18} className="text-accent" />
                            <span className="text-[10px] text-muted-foreground">Web</span>
                          </div>
                          <div className="flex flex-col items-center gap-2 p-2 rounded-lg bg-secondary/30">
                            <FileText weight="duotone" size={18} className="text-accent" />
                            <span className="text-[10px] text-muted-foreground">SharePoint</span>
                          </div>
                          <div className="flex flex-col items-center gap-2 p-2 rounded-lg bg-secondary/30">
                            <Cube weight="duotone" size={18} className="text-accent" />
                            <span className="text-[10px] text-muted-foreground">External</span>
                          </div>
                        </div>
                      </div>
                    </div>

                    <div className="p-5 rounded-2xl bg-background/60 border border-border/50 space-y-3">
                      <div className="flex items-center gap-3">
                        <Gear weight="duotone" size={20} className="text-accent" />
                        <span className="text-[14px] font-semibold">Tools</span>
                      </div>
                      <div className="grid grid-cols-3 gap-3">
                        <div className="p-3 rounded-lg bg-secondary/30 text-center">
                          <span className="text-[12px] font-medium">Power Platform</span>
                        </div>
                        <div className="p-3 rounded-lg bg-secondary/30 text-center">
                          <span className="text-[12px] font-medium">API Plugins</span>
                        </div>
                        <div className="p-3 rounded-lg bg-secondary/30 text-center">
                          <span className="text-[12px] font-medium">Custom</span>
                        </div>
                      </div>
                    </div>

                    <div className="p-5 rounded-2xl bg-background/60 border border-border/50">
                      <div className="flex items-center gap-3 mb-3">
                        <Brain weight="duotone" size={20} className="text-accent" />
                        <span className="text-[14px] font-semibold">General Capabilities</span>
                      </div>
                      <div className="grid grid-cols-2 gap-2">
                        <div className="p-2 rounded-lg bg-accent/5 text-center">
                          <span className="text-[11px]">Understanding</span>
                        </div>
                        <div className="p-2 rounded-lg bg-accent/5 text-center">
                          <span className="text-[11px]">Translation</span>
                        </div>
                        <div className="p-2 rounded-lg bg-accent/5 text-center">
                          <span className="text-[11px]">Summarization</span>
                        </div>
                        <div className="p-2 rounded-lg bg-accent/5 text-center">
                          <span className="text-[11px]">Custom Instructions</span>
                        </div>
                      </div>
                    </div>
                  </div>

                  <div className="pt-6 border-t border-border/50">
                    <div className="flex items-center gap-3 mb-4">
                      <div className="p-2 rounded-xl bg-gradient-to-br from-accent/20 to-accent/10">
                        <Brain weight="duotone" size={24} className="text-accent" />
                      </div>
                      <h3 className="text-[20px] font-semibold">Foundation Models</h3>
                    </div>
                    <div className="grid grid-cols-4 gap-3">
                      <div className="p-4 rounded-xl bg-gradient-to-br from-accent/10 to-accent/5 border border-accent/20 text-center space-y-2">
                        <Database weight="duotone" size={24} className="text-accent mx-auto" />
                        <span className="text-[12px] font-medium block">Cognitive Services</span>
                      </div>
                      <div className="p-4 rounded-xl bg-gradient-to-br from-accent/10 to-accent/5 border border-accent/20 text-center space-y-2">
                        <Target weight="duotone" size={24} className="text-accent mx-auto" />
                        <span className="text-[12px] font-medium block">Azure AI Search</span>
                      </div>
                      <div className="p-4 rounded-xl bg-gradient-to-br from-accent/10 to-accent/5 border border-accent/20 text-center space-y-2">
                        <Brain weight="duotone" size={24} className="text-accent mx-auto" />
                        <span className="text-[12px] font-medium block">Fine-tuning</span>
                      </div>
                      <div className="p-4 rounded-xl bg-gradient-to-br from-accent/10 to-accent/5 border border-accent/20 text-center space-y-2">
                        <Sparkle weight="duotone" size={24} className="text-accent mx-auto" />
                        <span className="text-[12px] font-medium block">Foundry IQ</span>
                      </div>
                    </div>
                  </div>
                </div>
              </motion.div>

              <motion.div
                initial={{ opacity: 0, x: 30 }}
                whileInView={{ opacity: 1, x: 0 }}
                viewport={{ once: true }}
                transition={{ duration: 0.6, delay: 0.2 }}
                className="lg:col-span-4 space-y-4"
              >
                <div className="p-6 rounded-3xl bg-gradient-to-br from-card to-card/50 border border-border/50">
                  <div className="flex items-center gap-3 mb-6">
                    <div className="p-2 rounded-xl bg-gradient-to-br from-accent/20 to-accent/10">
                      <Rocket weight="duotone" size={20} className="text-accent" />
                    </div>
                    <h3 className="text-[16px] font-semibold">Accelerators</h3>
                  </div>
                  <div className="space-y-3">
                    <div className="p-4 rounded-2xl bg-gradient-to-br from-accent/5 to-transparent border border-accent/10">
                      <div className="flex items-center gap-3 mb-2">
                        <VideoCamera weight="duotone" size={20} className="text-accent" />
                        <span className="text-[13px] font-semibold">Video RAG</span>
                      </div>
                      <p className="text-[11px] text-muted-foreground leading-relaxed">
                        Intelligent Q&A over training videos
                      </p>
                    </div>

                    <div className="p-4 rounded-2xl bg-gradient-to-br from-accent/5 to-transparent border border-accent/10">
                      <div className="flex items-center gap-3 mb-2">
                        <Database weight="duotone" size={20} className="text-accent" />
                        <span className="text-[13px] font-semibold">AISearch Flow</span>
                      </div>
                      <p className="text-[11px] text-muted-foreground leading-relaxed">
                        Manual control for indexing and semantic search
                      </p>
                    </div>

                    <div className="p-4 rounded-2xl bg-gradient-to-br from-accent/5 to-transparent border border-accent/10">
                      <div className="flex items-center gap-3 mb-2">
                        <FileText weight="duotone" size={20} className="text-accent" />
                        <span className="text-[13px] font-semibold">Content Flow</span>
                      </div>
                      <p className="text-[11px] text-muted-foreground leading-relaxed">
                        Automated document ingestion and chunking
                      </p>
                    </div>
                  </div>
                </div>
              </motion.div>
            </div>
          </div>
        </section>

        <section id="use-cases" className="py-32 md:py-40">
          <div className="max-w-[1400px] mx-auto px-6 lg:px-12">
            <motion.div
              initial={{ opacity: 0, y: 30 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ duration: 0.7 }}
              className="text-center space-y-6 mb-20 md:mb-28 max-w-[800px] mx-auto"
            >
              <h2 className="text-[48px] md:text-[64px] font-semibold tracking-[-0.03em] leading-tight">
                Real-world impact
              </h2>
              <p className="text-[20px] md:text-[22px] text-muted-foreground leading-relaxed font-light">
                See how organizations are transforming their operations with intelligent AI agents
              </p>
            </motion.div>

            <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
              {useCases.map((useCase, index) => (
                <motion.a
                  key={useCase.title}
                  href={useCase.link}
                  target="_blank"
                  rel="noopener noreferrer"
                  initial={{ opacity: 0, y: 30 }}
                  whileInView={{ opacity: 1, y: 0 }}
                  viewport={{ once: true }}
                  transition={{ duration: 0.5, delay: index * 0.1 }}
                  className="group p-10 rounded-3xl bg-card border border-border hover:border-accent/30 transition-all duration-500 hover:shadow-2xl hover:shadow-accent/5 hover:-translate-y-1 space-y-6"
                >
                  <div className="inline-flex p-4 rounded-2xl bg-accent/10 group-hover:bg-accent/20 transition-colors duration-300">
                    <useCase.icon weight="duotone" size={36} className="text-accent" />
                  </div>
                  <div className="space-y-4">
                    <h3 className="text-[24px] font-semibold tracking-tight group-hover:text-accent transition-colors duration-300">
                      {useCase.title}
                    </h3>
                    <p className="text-[17px] text-muted-foreground leading-relaxed font-light">
                      {useCase.description}
                    </p>
                  </div>
                </motion.a>
              ))}
            </div>
          </div>
        </section>

        <section id="accelerators" className="py-32 md:py-40">
          <div className="max-w-[1400px] mx-auto px-6 lg:px-12">
            <motion.div
              initial={{ opacity: 0, y: 30 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ duration: 0.7 }}
              className="text-center space-y-6 mb-20 md:mb-28 max-w-[800px] mx-auto"
            >
              <h2 className="text-[48px] md:text-[64px] font-semibold tracking-[-0.03em] leading-tight">
                Solution Accelerators
              </h2>
              <p className="text-[20px] md:text-[22px] text-muted-foreground leading-relaxed font-light">
                Pre-built solutions that expand core functionality and accelerate your development
              </p>
            </motion.div>

            <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
              {accelerators.map((accelerator, index) => (
                <motion.a
                  key={accelerator.title}
                  href={accelerator.link}
                  target="_blank"
                  rel="noopener noreferrer"
                  initial={{ opacity: 0, y: 30 }}
                  whileInView={{ opacity: 1, y: 0 }}
                  viewport={{ once: true }}
                  transition={{ duration: 0.5, delay: index * 0.1 }}
                  className="group relative p-10 rounded-3xl bg-card border border-border hover:border-accent/30 transition-all duration-500 hover:shadow-2xl hover:shadow-accent/5 hover:-translate-y-1"
                >
                  <div className="space-y-4">
                    <h3 className="text-[24px] font-semibold tracking-tight group-hover:text-accent transition-colors duration-300">
                      {accelerator.title}
                    </h3>
                    <p className="text-[17px] text-muted-foreground leading-relaxed font-light">
                      {accelerator.description}
                    </p>
                    <div className="flex items-center gap-2 text-accent font-medium text-[15px] pt-2 opacity-0 group-hover:opacity-100 transition-all duration-300 transform translate-y-2 group-hover:translate-y-0">
                      Learn more
                      <ArrowRight weight="bold" size={16} />
                    </div>
                  </div>
                </motion.a>
              ))}
            </div>
          </div>
        </section>

        <section className="py-32 md:py-40 bg-foreground text-background overflow-hidden relative">
          <div className="absolute inset-0 opacity-10">
            <div className="absolute top-1/4 left-1/4 w-[600px] h-[600px] bg-accent/30 rounded-full blur-[120px]"></div>
            <div className="absolute bottom-1/4 right-1/4 w-[600px] h-[600px] bg-accent/20 rounded-full blur-[120px]"></div>
          </div>
          
          <div className="relative max-w-[900px] mx-auto px-6 text-center space-y-10">
            <motion.div
              initial={{ opacity: 0, y: 30 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ duration: 0.7 }}
              className="space-y-8"
            >
              <div className="inline-flex p-4 rounded-2xl bg-accent/20 backdrop-blur-sm">
                <Rocket weight="duotone" size={40} className="text-background" />
              </div>
              
              <h2 className="text-[48px] md:text-[64px] font-semibold tracking-[-0.03em] leading-tight">
                Ready to transform
                <br />
                your enterprise?
              </h2>
              
              <p className="text-[20px] md:text-[22px] text-background/70 leading-relaxed font-light max-w-[650px] mx-auto">
                Join organizations building the future of enterprise AI with secure, scalable, and intelligent copilots.
              </p>
            </motion.div>

            <motion.div
              initial={{ opacity: 0, y: 30 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ duration: 0.7, delay: 0.2 }}
              className="flex flex-col sm:flex-row items-center justify-center gap-4 pt-4"
            >
              <Button 
                size="lg" 
                className="bg-background hover:bg-background/90 text-foreground px-8 h-[56px] text-[17px] font-medium rounded-full transition-all duration-300 hover:scale-[1.02] hover:shadow-2xl"
                asChild
              >
                <a href={REPO_URL} target="_blank" rel="noopener noreferrer" className="flex items-center gap-2">
                  <GithubLogo weight="fill" size={22} />
                  View on GitHub
                </a>
              </Button>
            </motion.div>
          </div>
        </section>
      </main>
      <footer className="py-12 border-t border-border/50">
        <div className="max-w-[1400px] mx-auto px-6 lg:px-12">
          <div className="flex flex-col md:flex-row items-center justify-between gap-6">
            <div className="flex items-center gap-2 text-muted-foreground text-[14px]">
              <div className="w-6 h-6 rounded-md bg-gradient-to-br from-accent to-accent/60 flex items-center justify-center">
                <Sparkle weight="fill" className="text-white" size={14} />
              </div>
              <span>Copilot Studio Empowered by Azure</span>
            </div>
            
            <div className="flex items-center gap-8 text-[14px] text-muted-foreground">
              <a 
                href={`${REPO_URL}/blob/main/LICENSE`} 
                target="_blank" 
                rel="noopener noreferrer" 
                className="hover:text-foreground transition-colors duration-200"
              >
                License
              </a>
              <a 
                href={`${REPO_URL}/blob/main/SECURITY.md`} 
                target="_blank" 
                rel="noopener noreferrer" 
                className="hover:text-foreground transition-colors duration-200"
              >
                Security
              </a>
              <a 
                href={`${REPO_URL}/blob/main/CONTRIBUTING.md`} 
                target="_blank" 
                rel="noopener noreferrer" 
                className="hover:text-foreground transition-colors duration-200"
              >
                Contributing
              </a>
            </div>
          </div>
        </div>
      </footer>
    </div>
  );
}

export default App
