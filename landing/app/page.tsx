import Hero from '@/components/Hero';
import EcosystemStatus from '@/components/EcosystemStatus';
import HowItWorks from '@/components/HowItWorks';
import Features from '@/components/Features';
import Platforms from '@/components/Platforms';
import Pricing from '@/components/Pricing';
import FAQ from '@/components/FAQ';
import FinalCTA from '@/components/FinalCTA';
import Footer from '@/components/Footer';
import Navigation from '@/components/Navigation';

export default function Home() {
  return (
    <>
      <Navigation />
      <main id="main">
        <Hero />
        <EcosystemStatus />
        <HowItWorks />
        <div className="grain bg-surface/30">
          <Features />
        </div>
        <Platforms />
        <div className="grain bg-surface/30">
          <Pricing />
        </div>
        <FAQ />
        <FinalCTA />
      </main>
      <Footer />
    </>
  );
}
